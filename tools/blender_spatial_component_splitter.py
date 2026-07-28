#!/usr/bin/env python3
"""Blender 空间分组拆分工具，用于将碎片化单网格导出为独立 GLB。"""

from __future__ import annotations

import argparse
import json
import math
import os
import random
import struct
import sys
import time
import traceback
from dataclasses import asdict, dataclass, field
from pathlib import Path
from typing import Any, Sequence

try:
    import bmesh
    import bpy
    from mathutils import Matrix, Vector
    from mathutils.kdtree import KDTree
except ModuleNotFoundError:  # 允许在普通 Python 中查看 --help。
    bmesh = None
    bpy = None
    Matrix = None
    Vector = None
    KDTree = None


TOOL_VERSION = "0.1.0"
MIN_BLENDER_VERSION = (4, 2, 0)
KMEANS_ATTEMPTS = 32
KMEANS_ITERATIONS = 100


class SplitError(RuntimeError):
    """拆分条件不可信时抛出，防止生成部分或错分结果。"""


@dataclass
class LooseComponent:
    vertex_indices: list[int]
    face_count: int
    minimum: Any
    maximum: Any

    @property
    def center(self) -> Any:
        return (self.minimum + self.maximum) * 0.5

    @property
    def weight(self) -> float:
        return max(1.0, math.sqrt(max(self.face_count, len(self.vertex_indices))))


@dataclass
class SplitGroup:
    component_indices: list[int]
    minimum: Any
    maximum: Any
    face_count: int
    vertex_indices: list[int]
    output_index: int = 0

    @property
    def center(self) -> Any:
        return (self.minimum + self.maximum) * 0.5


@dataclass
class SplitResult:
    status: str
    input_path: str
    output_dir: str
    requested_parts: int
    loose_component_count: int = 0
    duration_seconds: float = 0.0
    layout_axes: list[str] = field(default_factory=list)
    grid: str | None = None
    outputs: list[dict[str, Any]] = field(default_factory=list)
    error: str | None = None
    details: str | None = None


# 每次运行从空场景开始，避免启动文件对选择和导出造成干扰。
def reset_scene() -> None:
    if bpy.context.object is not None and bpy.context.object.mode != "OBJECT":
        bpy.ops.object.mode_set(mode="OBJECT")
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)


# 导入 GLB 并严格要求只有一个待拆 Mesh，避免在已是多对象的资产上重复拆分。
def import_single_mesh(path: Path) -> Any:
    if not path.is_file() or path.suffix.lower() != ".glb":
        raise SplitError(f"输入不是有效 GLB: {path}")
    result = bpy.ops.import_scene.gltf(filepath=str(path))
    if "FINISHED" not in result:
        raise SplitError(f"GLB 导入失败: {path}")
    meshes = [obj for obj in bpy.context.scene.objects if obj.type == "MESH"]
    if len(meshes) != 1:
        raise SplitError(f"待拆输入必须恰好有 1 个 Mesh，当前为 {len(meshes)} 个")
    mesh_object = meshes[0]
    if not mesh_object.data.vertices or not mesh_object.data.polygons:
        raise SplitError("待拆 Mesh 为空")
    if not mesh_object.data.uv_layers or mesh_object.data.uv_layers.active is None:
        raise SplitError("待拆 Mesh 没有活动 UV")
    return mesh_object


# 用边连通性恢复拓扑松散块，但只作为聚类原子，不直接创建数千个对象。
def find_loose_components(obj: Any) -> list[LooseComponent]:
    mesh = obj.data
    parent = list(range(len(mesh.vertices)))

    def find(index: int) -> int:
        while parent[index] != index:
            parent[index] = parent[parent[index]]
            index = parent[index]
        return index

    def union(left: int, right: int) -> None:
        left_root = find(left)
        right_root = find(right)
        if left_root != right_root:
            parent[right_root] = left_root

    for edge in mesh.edges:
        union(edge.vertices[0], edge.vertices[1])

    vertices_by_root: dict[int, list[int]] = {}
    faces_by_root: dict[int, int] = {}
    for vertex in mesh.vertices:
        vertices_by_root.setdefault(find(vertex.index), []).append(vertex.index)
    for polygon in mesh.polygons:
        root = find(polygon.vertices[0])
        faces_by_root[root] = faces_by_root.get(root, 0) + 1

    components: list[LooseComponent] = []
    for root, vertex_indices in vertices_by_root.items():
        points = [obj.matrix_world @ mesh.vertices[index].co for index in vertex_indices]
        minimum = Vector((min(point[axis] for point in points) for axis in range(3)))
        maximum = Vector((max(point[axis] for point in points) for axis in range(3)))
        components.append(
            LooseComponent(
                vertex_indices=vertex_indices,
                face_count=faces_by_root.get(root, 0),
                minimum=minimum,
                maximum=maximum,
            )
        )
    return components


# 选择整体尺寸最大的两个轴作为排列平面，自动忽略建筑组件的厚度轴。
def choose_layout_axes(components: Sequence[LooseComponent]) -> tuple[int, int]:
    minimum = Vector((min(component.minimum[axis] for component in components) for axis in range(3)))
    maximum = Vector((max(component.maximum[axis] for component in components) for axis in range(3)))
    dimensions = maximum - minimum
    axes = sorted(range(3), key=lambda axis: dimensions[axis], reverse=True)[:2]
    return axes[0], axes[1]


def squared_distance(left: Sequence[float], right: Sequence[float]) -> float:
    return sum((left[index] - right[index]) ** 2 for index in range(len(left)))


# 多次加权 K-Means++ 用空间中心将碎片聚合为指定数量的完整模块。
def cluster_components(
    components: Sequence[LooseComponent],
    part_count: int,
    layout_axes: tuple[int, int],
) -> list[int]:
    if part_count < 2:
        raise SplitError("拆分数量必须至少为 2")
    if len(components) < part_count:
        raise SplitError(f"松散块只有 {len(components)} 个，无法拆成 {part_count} 组")

    raw_points = [
        [component.center[layout_axes[0]], component.center[layout_axes[1]]]
        for component in components
    ]
    minimum = [min(point[axis] for point in raw_points) for axis in range(2)]
    maximum = [max(point[axis] for point in raw_points) for axis in range(2)]
    spans = [max(maximum[axis] - minimum[axis], 1e-8) for axis in range(2)]
    points = [
        [(point[axis] - minimum[axis]) / spans[axis] for axis in range(2)]
        for point in raw_points
    ]
    weights = [component.weight for component in components]

    best_assignments: list[int] | None = None
    best_score = math.inf
    for attempt in range(KMEANS_ATTEMPTS):
        rng = random.Random(104729 + attempt)
        first_index = rng.choices(range(len(points)), weights=weights, k=1)[0]
        centers = [list(points[first_index])]
        while len(centers) < part_count:
            probabilities = [
                min(squared_distance(point, center) for center in centers) * weights[index]
                for index, point in enumerate(points)
            ]
            if sum(probabilities) <= 1e-12:
                break
            centers.append(list(points[rng.choices(range(len(points)), weights=probabilities, k=1)[0]]))
        if len(centers) != part_count:
            continue

        assignments = [-1] * len(points)
        for _ in range(KMEANS_ITERATIONS):
            new_assignments = [
                min(range(part_count), key=lambda index: squared_distance(point, centers[index]))
                for point in points
            ]
            if new_assignments == assignments:
                break
            assignments = new_assignments
            new_centers: list[list[float]] = []
            valid = True
            for cluster_index in range(part_count):
                members = [index for index, value in enumerate(assignments) if value == cluster_index]
                if not members:
                    valid = False
                    break
                total_weight = sum(weights[index] for index in members)
                new_centers.append(
                    [
                        sum(points[index][axis] * weights[index] for index in members) / total_weight
                        for axis in range(2)
                    ]
                )
            if not valid:
                assignments = []
                break
            centers = new_centers
        if not assignments:
            continue
        score = sum(
            squared_distance(points[index], centers[assignments[index]]) * weights[index]
            for index in range(len(points))
        )
        if score < best_score:
            best_score = score
            best_assignments = list(assignments)

    if best_assignments is None:
        raise SplitError("空间聚类未能生成指定数量的非空分组")
    return best_assignments


# 规则阵列分别沿水平和垂直轴聚类，避免二维距离在行列交界处串组。
def cluster_components_grid(
    components: Sequence[LooseComponent],
    columns: int,
    rows: int,
    layout_axes: tuple[int, int],
) -> list[int]:
    if columns < 1 or rows < 1 or columns * rows < 2:
        raise SplitError("网格行列必须为正整数，且总组数至少为 2")
    horizontal_axis = next((axis for axis in layout_axes if axis != 2), layout_axes[0])
    vertical_axis = 2 if 2 in layout_axes else next(axis for axis in layout_axes if axis != horizontal_axis)
    weights = [component.weight for component in components]

    def cluster_one_axis(values: Sequence[float], count: int) -> tuple[list[int], list[float]]:
        if count == 1:
            return [0] * len(values), [sum(value * weight for value, weight in zip(values, weights)) / sum(weights)]
        ordered = sorted(range(len(values)), key=lambda index: values[index])
        total_weight = sum(weights)
        centers: list[float] = []
        for cluster_index in range(count):
            target = total_weight * (cluster_index + 0.5) / count
            accumulated = 0.0
            selected = ordered[-1]
            for index in ordered:
                accumulated += weights[index]
                if accumulated >= target:
                    selected = index
                    break
            centers.append(values[selected])
        assignments = [-1] * len(values)
        for _ in range(KMEANS_ITERATIONS):
            new_assignments = [
                min(range(count), key=lambda index: abs(value - centers[index]))
                for value in values
            ]
            if new_assignments == assignments:
                break
            assignments = new_assignments
            new_centers: list[float] = []
            for cluster_index in range(count):
                members = [index for index, value in enumerate(assignments) if value == cluster_index]
                if not members:
                    raise SplitError("网格单轴聚类出现空组")
                member_weight = sum(weights[index] for index in members)
                new_centers.append(
                    sum(values[index] * weights[index] for index in members) / member_weight
                )
            centers = new_centers
        center_order = sorted(range(count), key=lambda index: centers[index])
        remap = {old: new for new, old in enumerate(center_order)}
        return [remap[value] for value in assignments], [centers[index] for index in center_order]

    horizontal_values = [component.center[horizontal_axis] for component in components]
    vertical_values = [component.center[vertical_axis] for component in components]
    column_assignments, _ = cluster_one_axis(horizontal_values, columns)
    vertical_assignments, vertical_centers = cluster_one_axis(vertical_values, rows)
    vertical_order = sorted(range(rows), key=lambda index: vertical_centers[index], reverse=True)
    row_remap = {old: new for new, old in enumerate(vertical_order)}
    assignments = [
        row_remap[vertical_assignments[index]] * columns + column_assignments[index]
        for index in range(len(components))
    ]
    if len(set(assignments)) != columns * rows:
        raise SplitError("网格聚类未生成完整的行列组合")
    return assignments


# 固定每组大体量主体，再按三维包围盒距离重分配小碎片。
def refine_assignments_by_anchor_distance(
    source: Any,
    components: Sequence[LooseComponent],
    assignments: Sequence[int],
    part_count: int,
) -> list[int]:
    anchors_by_group: list[list[int]] = []
    anchor_indices: set[int] = set()
    for group_index in range(part_count):
        members = [index for index, value in enumerate(assignments) if value == group_index]
        if not members:
            raise SplitError(f"初始分组 {group_index + 1} 为空")
        members.sort(key=lambda index: components[index].face_count, reverse=True)
        group_faces = sum(components[index].face_count for index in members)
        selected: list[int] = []
        selected_faces = 0
        for index in members:
            selected.append(index)
            selected_faces += components[index].face_count
            if len(selected) >= 3 and selected_faces >= group_faces * 0.40:
                break
            if len(selected) >= 24:
                break
        anchors_by_group.append(selected)
        anchor_indices.update(selected)

    trees: list[Any] = []
    for anchor_indices in anchors_by_group:
        vertex_indices = sorted(
            {
                vertex_index
                for component_index in anchor_indices
                for vertex_index in components[component_index].vertex_indices
            }
        )
        tree = KDTree(len(vertex_indices))
        for tree_index, vertex_index in enumerate(vertex_indices):
            tree.insert(source.matrix_world @ source.data.vertices[vertex_index].co, tree_index)
        tree.balance()
        trees.append(tree)

    refined = list(assignments)
    for component_index, component in enumerate(components):
        if component_index in anchor_indices:
            continue
        sample_step = max(1, math.ceil(len(component.vertex_indices) / 24))
        sample_points = [
            source.matrix_world @ source.data.vertices[vertex_index].co
            for vertex_index in component.vertex_indices[::sample_step]
        ]

        def group_distance(group_index: int) -> float:
            distances = sorted(trees[group_index].find(point)[2] for point in sample_points)
            return distances[len(distances) // 2]

        refined[component_index] = min(range(part_count), key=group_distance)
    return refined


# 将聚类结果合并为可导出分组，并拒绝面数过少的明显错分。
def build_groups(
    components: Sequence[LooseComponent], assignments: Sequence[int], part_count: int
) -> list[SplitGroup]:
    groups: list[SplitGroup] = []
    total_faces = sum(component.face_count for component in components)
    for cluster_index in range(part_count):
        component_indices = [index for index, value in enumerate(assignments) if value == cluster_index]
        if not component_indices:
            raise SplitError(f"聚类组 {cluster_index + 1} 为空")
        selected = [components[index] for index in component_indices]
        minimum = Vector((min(component.minimum[axis] for component in selected) for axis in range(3)))
        maximum = Vector((max(component.maximum[axis] for component in selected) for axis in range(3)))
        face_count = sum(component.face_count for component in selected)
        if face_count < max(1, total_faces * 0.015):
            raise SplitError(
                f"聚类组 {cluster_index + 1} 仅占总面数 {face_count / total_faces:.1%}，结果不可信"
            )
        vertex_indices = sorted(
            index for component in selected for index in component.vertex_indices
        )
        groups.append(
            SplitGroup(
                component_indices=component_indices,
                minimum=minimum,
                maximum=maximum,
                face_count=face_count,
                vertex_indices=vertex_indices,
            )
        )
    return groups


# 按高度先分行，再在每行内沿水平主轴排序，得到稳定的 01..NN 编号。
def order_groups(groups: list[SplitGroup], layout_axes: tuple[int, int]) -> list[SplitGroup]:
    horizontal_axis = next((axis for axis in layout_axes if axis != 2), layout_axes[0])
    median_height = sorted(max(group.maximum.z - group.minimum.z, 1e-6) for group in groups)[len(groups) // 2]
    row_tolerance = median_height * 0.4
    rows: list[list[SplitGroup]] = []
    for group in sorted(groups, key=lambda item: item.center.z, reverse=True):
        matching_row = next(
            (
                row
                for row in rows
                if abs(group.center.z - sum(item.center.z for item in row) / len(row)) <= row_tolerance
            ),
            None,
        )
        if matching_row is None:
            rows.append([group])
        else:
            matching_row.append(group)

    ordered: list[SplitGroup] = []
    for row in sorted(rows, key=lambda items: sum(item.center.z for item in items) / len(items), reverse=True):
        ordered.extend(sorted(row, key=lambda item: item.center[horizontal_axis]))
    for output_index, group in enumerate(ordered, start=1):
        group.output_index = output_index
    return ordered


# 复制原网格后只删除非本组顶点，保留 UV、材质索引和网格自定义数据。
def create_group_object(source: Any, group: SplitGroup, name: str) -> tuple[Any, Any]:
    copied_mesh = source.data.copy()
    copied_mesh.name = f"{name}_Mesh"
    bm = bmesh.new()
    bm.from_mesh(copied_mesh)
    bm.verts.ensure_lookup_table()
    keep = set(group.vertex_indices)
    delete_vertices = [vertex for vertex in bm.verts if vertex.index not in keep]
    bmesh.ops.delete(bm, geom=delete_vertices, context="VERTS")
    bm.to_mesh(copied_mesh)
    bm.free()
    copied_mesh.update()

    anchor = Vector(
        (
            (group.minimum.x + group.maximum.x) * 0.5,
            (group.minimum.y + group.maximum.y) * 0.5,
            group.minimum.z,
        )
    )
    copied_mesh.transform(Matrix.Translation(-anchor) @ source.matrix_world)
    split_object = source.copy()
    split_object.data = copied_mesh
    split_object.name = name
    split_object.parent = None
    split_object.matrix_world = Matrix.Identity(4)
    bpy.context.scene.collection.objects.link(split_object)
    return split_object, anchor


# 根据当前 Blender 版本过滤 glTF 导出参数，减少小版本 API 差异。
def supported_operator_kwargs(operator: Any, values: dict[str, Any]) -> dict[str, Any]:
    supported = {prop.identifier for prop in operator.get_rna_type().properties}
    return {key: value for key, value in values.items() if key in supported}


# 单次只导出一个拆分对象，使每个 GLB 独立且不带入其他组件。
def export_object(obj: Any, output_path: Path) -> None:
    bpy.ops.object.select_all(action="DESELECT")
    obj.hide_set(False)
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    kwargs = supported_operator_kwargs(
        bpy.ops.export_scene.gltf,
        {
            "filepath": str(output_path),
            "export_format": "GLB",
            "use_selection": True,
            "export_texcoords": True,
            "export_normals": True,
            "export_tangents": True,
            "export_materials": "EXPORT",
            "export_image_format": "AUTO",
            "export_animations": False,
            "export_yup": True,
        },
    )
    result = bpy.ops.export_scene.gltf(**kwargs)
    if "FINISHED" not in result:
        raise SplitError(f"GLB 导出失败: {output_path}")


# 解析导出 GLB，确认只含一个网格且原材质法线仍为内嵌引用。
def validate_export(path: Path, expected_name: str, require_normal: bool) -> dict[str, int]:
    with path.open("rb") as stream:
        magic, version, declared_length = struct.unpack("<4sII", stream.read(12))
        if magic != b"glTF" or version != 2 or declared_length != path.stat().st_size:
            raise SplitError(f"导出文件不是完整 glTF 2.0 Binary: {path}")
        chunk_length, chunk_type = struct.unpack("<II", stream.read(8))
        if chunk_type != 0x4E4F534A:
            raise SplitError(f"导出 GLB 缺少 JSON 块: {path}")
        document = json.loads(stream.read(chunk_length).decode("utf-8").rstrip("\x00 \t\r\n"))
    nodes = document.get("nodes", [])
    meshes = document.get("meshes", [])
    materials = document.get("materials", [])
    images = document.get("images", [])
    if len(meshes) != 1 or expected_name not in {node.get("name") for node in nodes}:
        raise SplitError(f"导出 GLB 未保留单对象结构: {path}")
    normal_count = sum(isinstance(material.get("normalTexture"), dict) for material in materials)
    if require_normal and normal_count == 0:
        raise SplitError(f"导出 GLB 丢失原法线材质: {path}")
    if any("uri" in image for image in images):
        raise SplitError(f"导出 GLB 出现外部图像引用: {path}")
    return {
        "nodes": len(nodes),
        "meshes": len(meshes),
        "materials": len(materials),
        "images": len(images),
        "normal_materials": normal_count,
    }


# 检查原点已在几何底部中心，不用导出成功代替空间验证。
def validate_bottom_center_origin(obj: Any) -> dict[str, float]:
    points = [obj.matrix_world @ Vector(corner) for corner in obj.bound_box]
    minimum = Vector((min(point[axis] for point in points) for axis in range(3)))
    maximum = Vector((max(point[axis] for point in points) for axis in range(3)))
    diagonal = max((maximum - minimum).length, 1e-8)
    center_x = (minimum.x + maximum.x) * 0.5
    center_y = (minimum.y + maximum.y) * 0.5
    tolerance = max(1e-6, diagonal * 1e-5)
    if abs(center_x) > tolerance or abs(center_y) > tolerance or abs(minimum.z) > tolerance:
        raise SplitError(
            f"对象 {obj.name} 原点未位于底部中心: "
            f"center=({center_x:.8f}, {center_y:.8f}), min_z={minimum.z:.8f}"
        )
    return {
        "origin_center_x": round(center_x, 8),
        "origin_center_y": round(center_y, 8),
        "origin_bottom_z": round(float(minimum.z), 8),
    }


# 在临时目录中完成全部导出，所有组验证后再整体移入正式目录。
def split_model(
    input_path: Path,
    output_dir: Path,
    name: str,
    part_count: int,
    overwrite: bool,
    grid: tuple[int, int] | None,
) -> SplitResult:
    started = time.perf_counter()
    result = SplitResult(
        status="failed",
        input_path=str(input_path),
        output_dir=str(output_dir),
        requested_parts=part_count,
        grid=f"{grid[0]}x{grid[1]}" if grid else None,
    )
    staging_dir = output_dir.with_name(f"{output_dir.name}.partial")
    try:
        expected_paths = [output_dir / f"{name}_{index:02d}.glb" for index in range(1, part_count + 1)]
        expected_names = {path.name for path in expected_paths}
        if output_dir.exists() and any(output_dir.iterdir()):
            if not overwrite:
                raise SplitError(f"输出目录非空，未启用覆盖: {output_dir}")
            unexpected = [child.name for child in output_dir.iterdir() if not child.is_file() or child.name not in expected_names]
            if unexpected:
                raise SplitError(
                    "输出目录含有非本工具目标，拒绝覆盖: " + ", ".join(sorted(unexpected))
                )
        if staging_dir.exists():
            unexpected = [child.name for child in staging_dir.iterdir() if not child.is_file() or child.name not in expected_names]
            if unexpected:
                raise SplitError(
                    "临时目录含有未识别文件，拒绝清理: " + ", ".join(sorted(unexpected))
                )
            for child in staging_dir.iterdir():
                child.unlink()
            staging_dir.rmdir()
        staging_dir.mkdir(parents=True)

        reset_scene()
        source = import_single_mesh(input_path)
        require_normal = any(
            slot.material
            and slot.material.node_tree
            and any(node.bl_idname == "ShaderNodeNormalMap" for node in slot.material.node_tree.nodes)
            for slot in source.material_slots
        )
        components = find_loose_components(source)
        result.loose_component_count = len(components)
        layout_axes = choose_layout_axes(components)
        result.layout_axes = ["XYZ"[axis] for axis in layout_axes]
        if grid is not None:
            if grid[0] * grid[1] != part_count:
                raise SplitError(
                    f"网格 {grid[0]}x{grid[1]} 与期望组数 {part_count} 不一致"
                )
            assignments = cluster_components_grid(components, grid[0], grid[1], layout_axes)
        else:
            assignments = cluster_components(components, part_count, layout_axes)
        assignments = refine_assignments_by_anchor_distance(source, components, assignments, part_count)
        groups = order_groups(build_groups(components, assignments, part_count), layout_axes)

        source.hide_set(True)
        source.hide_render = True
        for group in groups:
            part_name = f"{name}_{group.output_index:02d}"
            split_object, original_anchor = create_group_object(source, group, part_name)
            origin_info = validate_bottom_center_origin(split_object)
            temporary_path = staging_dir / f"{part_name}.glb"
            export_object(split_object, temporary_path)
            export_info = validate_export(temporary_path, part_name, require_normal)
            result.outputs.append(
                {
                    "name": part_name,
                    "path": str(output_dir / temporary_path.name),
                    "component_count": len(group.component_indices),
                    "face_count": group.face_count,
                    "original_anchor": [round(float(value), 8) for value in original_anchor],
                    "original_bounds_min": [round(float(value), 8) for value in group.minimum],
                    "original_bounds_max": [round(float(value), 8) for value in group.maximum],
                    **origin_info,
                    "export": export_info,
                }
            )
            split_mesh = split_object.data
            bpy.data.objects.remove(split_object, do_unlink=True)
            if split_mesh.users == 0:
                bpy.data.meshes.remove(split_mesh)

        output_dir.parent.mkdir(parents=True, exist_ok=True)
        if output_dir.exists():
            if not overwrite:
                raise SplitError(f"输出目录在处理期间被创建: {output_dir}")
            for child in output_dir.iterdir():
                child.unlink()
            output_dir.rmdir()
        os.replace(staging_dir, output_dir)
        result.status = "success"
    except Exception as exc:
        result.error = str(exc)
        result.details = traceback.format_exc()
    finally:
        result.duration_seconds = round(time.perf_counter() - started, 3)
    return result


# 原子写入 JSON 报告，保留每组的原始坐标和空间边界。
def write_report(result: SplitResult, path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(f"{path.name}.partial")
    temporary.write_text(json.dumps(asdict(result), ensure_ascii=False, indent=2), encoding="utf-8")
    os.replace(temporary, path)


# Blender 命令行参数位于 -- 之后，与 Blender 自身参数分开解析。
def tool_arguments(argv: Sequence[str]) -> list[str]:
    return list(argv[argv.index("--") + 1 :]) if "--" in argv else list(argv[1:])


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="将单 Mesh 中空间分离的大模块拆成指定数量的独立 GLB。")
    parser.add_argument("--input", type=Path, required=True, help="待拆 GLB")
    parser.add_argument("--output-dir", type=Path, required=True, help="独立 GLB 输出目录")
    parser.add_argument("--parts", type=int, required=True, help="期望的大模块数")
    parser.add_argument("--grid", help="规则阵列的列x行，例如 4x2")
    parser.add_argument("--name", help="输出名称前缀，默认为输入文件名")
    parser.add_argument("--report", type=Path, help="JSON 报告路径")
    parser.add_argument("--overwrite", action="store_true")
    parser.add_argument("--version", action="version", version=TOOL_VERSION)
    return parser


def run(argv: Sequence[str]) -> int:
    parser = build_parser()
    args = parser.parse_args(tool_arguments(argv))
    if bpy is None:
        parser.error("必须由 Blender Python 运行此工具")
    if bpy.app.version < MIN_BLENDER_VERSION:
        raise SplitError(
            f"需要 Blender {'.'.join(map(str, MIN_BLENDER_VERSION))} 或更高版本，"
            f"当前为 {bpy.app.version_string}"
        )
    input_path = args.input.expanduser().resolve()
    output_dir = args.output_dir.expanduser().resolve()
    name = args.name or input_path.stem
    grid = None
    if args.grid:
        match = args.grid.lower().split("x")
        if len(match) != 2 or not all(value.isdigit() for value in match):
            parser.error("--grid 必须使用列x行格式，例如 4x2")
        grid = (int(match[0]), int(match[1]))
    report_path = (
        args.report.expanduser().resolve()
        if args.report
        else output_dir.parent / f"{name}.split-report.json"
    )
    result = split_model(input_path, output_dir, name, args.parts, args.overwrite, grid)
    write_report(result, report_path)
    if result.status == "success":
        print(f"[SpatialSplitter] SUCCESS {name}: {len(result.outputs)} parts -> {output_dir}")
        return 0
    print(f"[SpatialSplitter] FAILED {name}: {result.error}", file=sys.stderr)
    return 1


if __name__ == "__main__":
    try:
        raise SystemExit(run(sys.argv))
    except SplitError as exc:
        print(f"[SpatialSplitter] FATAL: {exc}", file=sys.stderr)
        raise SystemExit(2)
