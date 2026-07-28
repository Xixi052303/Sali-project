#!/usr/bin/env python3
"""Blender 高低模切线空间法线批量烘焙工具。"""

from __future__ import annotations

import argparse
import json
import math
import os
import re
import struct
import sys
import time
import traceback
from dataclasses import asdict, dataclass, field
from pathlib import Path
from typing import Any, Iterable, Sequence

try:
    import bpy
    from mathutils import Vector
    from mathutils.bvhtree import BVHTree
except ModuleNotFoundError:  # 允许在普通 Python 中查看 --help。
    bpy = None
    Vector = None
    BVHTree = None


TOOL_VERSION = "0.1.0"
MIN_BLENDER_VERSION = (4, 2, 0)
DEFAULT_RESOLUTION = 2048
DEFAULT_EXTRUSION = 0.1
DEFAULT_MARGIN = 16
MAX_SURFACE_SAMPLES = 512


class BakeError(RuntimeError):
    """单个模型任务不可继续时抛出，不中断其他批处理任务。"""


@dataclass
class BakeTask:
    name: str
    high_path: Path
    low_path: Path
    output_path: Path
    resolution: int = DEFAULT_RESOLUTION
    extrusion: float = DEFAULT_EXTRUSION
    margin: int = DEFAULT_MARGIN
    overwrite: bool = False


@dataclass
class ObjectPair:
    low: Any
    high_sources: list[Any]
    reason: str


@dataclass
class Bounds:
    minimum: Any
    maximum: Any

    @property
    def center(self) -> Any:
        return (self.minimum + self.maximum) * 0.5

    @property
    def dimensions(self) -> Any:
        return self.maximum - self.minimum

    @property
    def diagonal(self) -> float:
        return float(self.dimensions.length)


@dataclass
class BakeResult:
    name: str
    status: str
    high_path: str
    low_path: str
    output_path: str
    duration_seconds: float = 0.0
    baked_objects: list[dict[str, Any]] = field(default_factory=list)
    warnings: list[str] = field(default_factory=list)
    error: str | None = None
    details: str | None = None


@dataclass
class RunReport:
    tool_version: str
    blender_version: str
    started_at: str
    finished_at: str = ""
    success_count: int = 0
    failure_count: int = 0
    results: list[BakeResult] = field(default_factory=list)


# 从低模文件名推导可读资产名，特殊命名仍可通过 --name 覆盖。
def derive_asset_name(low_path: Path) -> str:
    stem = low_path.stem.strip()
    stripped = re.sub(r"(?i)(?:[ _.-]?(?:low|med))$", "", stem).strip(" _.-")
    return stripped or stem


# 只接受 GLB 输入输出，避免分离纹理与运行规则不一致。
def validate_task_paths(task: BakeTask) -> None:
    for label, path in (("高模", task.high_path), ("低模", task.low_path)):
        if not path.is_file():
            raise BakeError(f"{label}文件不存在: {path}")
        if path.suffix.lower() != ".glb":
            raise BakeError(f"{label}必须是 .glb 文件: {path}")
    if task.output_path.suffix.lower() != ".glb":
        raise BakeError(f"输出必须是 .glb 文件: {task.output_path}")
    source_paths = {task.high_path.resolve(), task.low_path.resolve()}
    if task.output_path.resolve() in source_paths:
        raise BakeError("输出路径不能覆盖高模或低模源文件")
    if task.output_path.exists() and not task.overwrite:
        raise BakeError(f"输出已存在，未启用覆盖: {task.output_path}")
    if task.resolution < 4 or task.resolution > 16384:
        raise BakeError("纹理尺寸必须在 4 到 16384 之间")
    if task.extrusion <= 0.0:
        raise BakeError("挤出距离必须大于 0")
    if task.margin < 0:
        raise BakeError("边缘扩展不能小于 0")


# 每个任务从空场景开始，避免前一次失败留下的对象干扰选择与导出。
def reset_scene() -> None:
    bpy.ops.object.mode_set(mode="OBJECT") if bpy.context.object and bpy.context.object.mode != "OBJECT" else None
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    for datablocks in (
        bpy.data.meshes,
        bpy.data.curves,
        bpy.data.materials,
        bpy.data.images,
        bpy.data.cameras,
        bpy.data.lights,
        bpy.data.armatures,
        bpy.data.actions,
    ):
        for datablock in list(datablocks):
            if datablock.users == 0:
                datablocks.remove(datablock)


# 导入后按对象身份记录归属，高低模同名时也不依赖 Blender 的 .001 后缀。
def import_glb(path: Path) -> list[Any]:
    before = {obj.as_pointer() for obj in bpy.data.objects}
    result = bpy.ops.import_scene.gltf(filepath=str(path))
    if "FINISHED" not in result:
        raise BakeError(f"GLB 导入失败: {path}")
    imported = [obj for obj in bpy.data.objects if obj.as_pointer() not in before]
    if not imported:
        raise BakeError(f"GLB 未导入任何对象: {path}")
    return imported


# 计算对象或对象集的世界空间包围盒。
def world_bounds(objects: Iterable[Any]) -> Bounds:
    points: list[Any] = []
    for obj in objects:
        if obj.type != "MESH":
            continue
        points.extend(obj.matrix_world @ Vector(corner) for corner in obj.bound_box)
    if not points:
        raise BakeError("无法计算空网格集的包围盒")
    minimum = Vector((min(p[i] for p in points) for i in range(3)))
    maximum = Vector((max(p[i] for p in points) for i in range(3)))
    return Bounds(minimum, maximum)


# 对象配对成本同时考虑世界中心、尺寸和原点，不使用顶点数代替几何对齐。
def pairing_cost(low: Any, high: Any) -> float:
    low_bounds = world_bounds([low])
    high_bounds = world_bounds([high])
    scale = max(low_bounds.diagonal, high_bounds.diagonal, 1e-6)
    center_cost = (low_bounds.center - high_bounds.center).length / scale
    dimension_cost = sum(
        abs(low_bounds.dimensions[i] - high_bounds.dimensions[i])
        / max(abs(low_bounds.dimensions[i]), abs(high_bounds.dimensions[i]), scale * 1e-4)
        for i in range(3)
    )
    origin_cost = (low.matrix_world.translation - high.matrix_world.translation).length / scale
    return float(center_cost * 4.0 + dimension_cost + origin_cost * 0.25)


# 先配唯一同名对象，再对剩余网格做保守的一对一几何配对。
def pair_mesh_objects(low_meshes: Sequence[Any], high_meshes: Sequence[Any]) -> list[ObjectPair]:
    if not low_meshes:
        raise BakeError("低模中没有 Mesh 对象")
    if not high_meshes:
        raise BakeError("高模中没有 Mesh 对象")

    remaining_low = list(low_meshes)
    remaining_high = list(high_meshes)
    pairs: list[ObjectPair] = []

    low_by_name: dict[str, list[Any]] = {}
    high_by_name: dict[str, list[Any]] = {}
    for obj in remaining_low:
        low_by_name.setdefault(re.sub(r"\.\d{3}$", "", obj.name), []).append(obj)
    for obj in remaining_high:
        high_by_name.setdefault(re.sub(r"\.\d{3}$", "", obj.name), []).append(obj)

    for name in sorted(set(low_by_name) & set(high_by_name)):
        if len(low_by_name[name]) == 1 and len(high_by_name[name]) == 1:
            low_obj = low_by_name[name][0]
            high_obj = high_by_name[name][0]
            pairs.append(ObjectPair(low_obj, [high_obj], "唯一同名"))
            remaining_low.remove(low_obj)
            remaining_high.remove(high_obj)

    if not remaining_low:
        return pairs

    if len(remaining_low) == 1 and remaining_high:
        pairs.append(ObjectPair(remaining_low[0], list(remaining_high), "剩余高模网格联合"))
        return pairs

    if len(remaining_low) != len(remaining_high):
        raise BakeError(
            "无法可信配对高低模对象: "
            f"剩余低模 {len(remaining_low)} 个，高模 {len(remaining_high)} 个"
        )

    candidates = sorted(
        (pairing_cost(low, high), low, high)
        for low in remaining_low
        for high in remaining_high
    )
    used_low: set[int] = set()
    used_high: set[int] = set()
    for cost, low_obj, high_obj in candidates:
        low_key = low_obj.as_pointer()
        high_key = high_obj.as_pointer()
        if low_key in used_low or high_key in used_high:
            continue
        pairs.append(ObjectPair(low_obj, [high_obj], f"几何匹配 cost={cost:.4f}"))
        used_low.add(low_key)
        used_high.add(high_key)

    if len(used_low) != len(remaining_low):
        raise BakeError("高低模对象配对未完成")
    return pairs


# 在烘焙前校验 UV、可见几何和非退化包围盒。
def validate_low_mesh(low: Any) -> None:
    if not low.data.vertices or not low.data.polygons:
        raise BakeError(f"低模对象为空: {low.name}")
    if not low.data.uv_layers or low.data.uv_layers.active is None:
        raise BakeError(f"低模对象没有活动 UV: {low.name}")
    bounds = world_bounds([low])
    if bounds.diagonal <= 1e-8:
        raise BakeError(f"低模对象尺寸退化: {low.name}")


# 用世界包围盒和低模表面抽样距离验证重合，全程不改写任何变换。
def validate_alignment(pair: ObjectPair, extrusion: float) -> dict[str, Any]:
    low_bounds = world_bounds([pair.low])
    high_bounds = world_bounds(pair.high_sources)
    scale = max(low_bounds.diagonal, high_bounds.diagonal, 1e-6)
    center_delta = float((low_bounds.center - high_bounds.center).length)
    center_limit = max(0.001, scale * 0.08)
    dimension_error = max(
        abs(low_bounds.dimensions[i] - high_bounds.dimensions[i])
        / max(abs(low_bounds.dimensions[i]), abs(high_bounds.dimensions[i]), scale * 1e-4)
        for i in range(3)
    )
    if center_delta > center_limit or dimension_error > 0.30:
        raise BakeError(
            f"对象 {pair.low.name} 高低模包围盒不可信: "
            f"中心偏差 {center_delta:.6f}m，尺寸相对偏差 {dimension_error:.3f}"
        )

    depsgraph = bpy.context.evaluated_depsgraph_get()
    bvh_entries: list[tuple[Any, Any, Any]] = []
    for high in pair.high_sources:
        bvh = BVHTree.FromObject(high, depsgraph, deform=True, cage=False)
        if bvh is not None:
            bvh_entries.append((high, bvh, high.matrix_world.inverted_safe()))
    if not bvh_entries:
        raise BakeError(f"高模无法建立表面检查结构: {pair.low.name}")

    vertices = pair.low.data.vertices
    step = max(1, math.ceil(len(vertices) / MAX_SURFACE_SAMPLES))
    distances: list[float] = []
    for vertex_index in range(0, len(vertices), step):
        vertex = vertices[vertex_index]
        world_point = pair.low.matrix_world @ vertex.co
        nearest_distance = math.inf
        for high, bvh, inverse_world in bvh_entries:
            nearest = bvh.find_nearest(inverse_world @ world_point)
            if nearest is None or nearest[0] is None:
                continue
            nearest_world = high.matrix_world @ nearest[0]
            nearest_distance = min(nearest_distance, float((nearest_world - world_point).length))
        distances.append(nearest_distance)

    if not distances or not all(math.isfinite(distance) for distance in distances):
        raise BakeError(f"表面距离检查失败: {pair.low.name}")
    allowed = extrusion + max(0.0001, scale * 0.001)
    covered = sum(distance <= allowed for distance in distances)
    coverage = covered / len(distances)
    max_distance = max(distances)
    if coverage < 0.98:
        raise BakeError(
            f"对象 {pair.low.name} 不在 {extrusion:.4f}m 可信投射范围内: "
            f"抽样覆盖率 {coverage:.1%}，最大距离 {max_distance:.6f}m"
        )
    return {
        "pairing": pair.reason,
        "high_objects": [obj.name for obj in pair.high_sources],
        "center_delta_m": round(center_delta, 8),
        "dimension_relative_error": round(float(dimension_error), 6),
        "surface_sample_count": len(distances),
        "surface_coverage": round(coverage, 6),
        "surface_max_distance_m": round(max_distance, 8),
    }


# 确保材质有一条 glTF 导出器可识别的 Image Texture -> Normal Map -> Principled 链路。
def prepare_material_for_bake(obj: Any, slot_index: int, image: Any) -> Any:
    slot = obj.material_slots[slot_index]
    source_material = slot.material
    if source_material is None:
        material = bpy.data.materials.new(name=f"{obj.name}_Material_{slot_index + 1}")
    else:
        material = source_material.copy()
        material.name = f"{source_material.name}__normal_baked_{obj.name}_{slot_index + 1}"
    if bpy.app.version < (5, 0, 0):
        material.use_nodes = True
    slot.material = material

    if material.node_tree is None:
        raise BakeError(f"材质无法创建着色器节点树: {material.name}")
    nodes = material.node_tree.nodes
    output = next(
        (node for node in nodes if node.bl_idname == "ShaderNodeOutputMaterial" and node.is_active_output),
        None,
    )
    principled = None
    if output is not None and output.inputs["Surface"].is_linked:
        upstream = output.inputs["Surface"].links[0].from_node
        if upstream.bl_idname == "ShaderNodeBsdfPrincipled":
            principled = upstream
    if principled is None:
        principled = next((node for node in nodes if node.bl_idname == "ShaderNodeBsdfPrincipled"), None)
    if principled is None:
        raise BakeError(f"材质中找不到 Principled BSDF: {material.name}")

    image_node = nodes.new("ShaderNodeTexImage")
    image_node.name = "Baked Normal Image"
    image_node.label = "Baked Normal"
    image_node.image = image
    image_node.interpolation = "Linear"
    image_node.location = (principled.location.x - 600.0, principled.location.y - 220.0)

    normal_node = nodes.new("ShaderNodeNormalMap")
    normal_node.name = "Baked Normal Map"
    normal_node.label = "Baked Normal"
    normal_node.space = "TANGENT"
    normal_node.inputs["Strength"].default_value = 1.0
    normal_node.location = (principled.location.x - 320.0, principled.location.y - 220.0)

    for node in nodes:
        node.select = False
    image_node.select = True
    nodes.active = image_node
    return material


# 在烘焙完成后再接入法线链路，避免 Cycles 把烘焙目标图像误判为输入循环。
def connect_baked_materials(obj: Any) -> None:
    for slot in obj.material_slots:
        material = slot.material
        if material is None or material.node_tree is None:
            raise BakeError(f"低模对象存在无效材质: {obj.name}")
        nodes = material.node_tree.nodes
        links = material.node_tree.links
        image_node = nodes.get("Baked Normal Image")
        normal_node = nodes.get("Baked Normal Map")
        output = next(
            (node for node in nodes if node.bl_idname == "ShaderNodeOutputMaterial" and node.is_active_output),
            None,
        )
        principled = None
        if output is not None and output.inputs["Surface"].is_linked:
            upstream = output.inputs["Surface"].links[0].from_node
            if upstream.bl_idname == "ShaderNodeBsdfPrincipled":
                principled = upstream
        if principled is None:
            principled = next((node for node in nodes if node.bl_idname == "ShaderNodeBsdfPrincipled"), None)
        if image_node is None or normal_node is None or principled is None:
            raise BakeError(f"无法完成法线节点连接: {material.name}")
        normal_input = principled.inputs.get("Normal")
        if normal_input is None:
            raise BakeError(f"Principled BSDF 没有 Normal 输入: {material.name}")
        for link in list(normal_input.links):
            links.remove(link)
        links.new(image_node.outputs["Color"], normal_node.inputs["Color"])
        links.new(normal_node.outputs["Normal"], normal_input)


# 为每个材质槽使用独立图像，避免多对象或多材质 UV 重叠时互相覆盖。
def prepare_bake_targets(obj: Any, resolution: int) -> list[Any]:
    if len(obj.material_slots) == 0:
        obj.data.materials.append(None)
    images: list[Any] = []
    for slot_index in range(len(obj.material_slots)):
        image = bpy.data.images.new(
            name="法向.png",
            width=resolution,
            height=resolution,
            alpha=False,
            float_buffer=False,
            is_data=True,
        )
        image.generated_color = (0.5, 0.5, 1.0, 1.0)
        image.colorspace_settings.name = "Non-Color"
        prepare_material_for_bake(obj, slot_index, image)
        images.append(image)
    return images


# 显式写入全部烘焙参数，不继承启动文件或上次操作状态。
def configure_cycles_bake(task: BakeTask) -> None:
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    bake = scene.render.bake
    bake.target = "IMAGE_TEXTURES"
    bake.use_selected_to_active = True
    bake.use_cage = False
    bake.cage_extrusion = task.extrusion
    bake.max_ray_distance = 0.0
    bake.normal_space = "TANGENT"
    bake.normal_r = "POS_X"
    bake.normal_g = "POS_Y"
    bake.normal_b = "POS_Z"
    bake.margin = task.margin
    if hasattr(bake, "margin_type"):
        bake.margin_type = "EXTEND"
    bake.use_clear = True


# 严格按“高模源 -> 活动低模”选择后执行一次法线烘焙。
def bake_object(pair: ObjectPair, task: BakeTask) -> list[Any]:
    images = prepare_bake_targets(pair.low, task.resolution)
    bpy.ops.object.select_all(action="DESELECT")
    for source in pair.high_sources:
        source.hide_render = False
        source.hide_set(False)
        source.select_set(True)
    pair.low.hide_render = False
    pair.low.hide_set(False)
    pair.low.select_set(True)
    bpy.context.view_layer.objects.active = pair.low
    result = bpy.ops.object.bake(type="NORMAL")
    if "FINISHED" not in result:
        raise BakeError(f"法线烘焙失败: {pair.low.name}")
    connect_baked_materials(pair.low)
    for image in images:
        image.update()
        try:
            image.pack()
        except RuntimeError:
            pass
    return images


# 根据当前 Blender 的 glTF 操作符属性过滤参数，兼容 4.2+与后续版本小幅 API 变化。
def supported_operator_kwargs(operator: Any, values: dict[str, Any]) -> dict[str, Any]:
    supported = {prop.identifier for prop in operator.get_rna_type().properties}
    return {key: value for key, value in values.items() if key in supported}


# 只选中低模导入的对象，保留其父子层级、非网格节点、材质和动画。
def export_low_glb(low_objects: Sequence[Any], output_path: Path) -> None:
    bpy.ops.object.select_all(action="DESELECT")
    for obj in low_objects:
        obj.hide_set(False)
        obj.select_set(True)
    if not low_objects:
        raise BakeError("没有可导出的低模对象")
    bpy.context.view_layer.objects.active = next(
        (obj for obj in low_objects if obj.type == "MESH"), low_objects[0]
    )
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
            "export_animations": True,
            "export_yup": True,
        },
    )
    result = bpy.ops.export_scene.gltf(**kwargs)
    if "FINISHED" not in result:
        raise BakeError(f"GLB 导出失败: {output_path}")


# 直接解析 GLB JSON 块，确认法线材质和图像都已内嵌而非外链。
def validate_exported_glb(path: Path, expected_objects: Sequence[Any]) -> dict[str, int]:
    with path.open("rb") as stream:
        header = stream.read(12)
        if len(header) != 12:
            raise BakeError("导出 GLB 头部不完整")
        magic, version, declared_length = struct.unpack("<4sII", header)
        if magic != b"glTF" or version != 2:
            raise BakeError("导出文件不是有效的 glTF 2.0 Binary")
        if declared_length != path.stat().st_size:
            raise BakeError("导出 GLB 长度字段与文件大小不一致")
        chunk_length, chunk_type = struct.unpack("<II", stream.read(8))
        if chunk_type != 0x4E4F534A:
            raise BakeError("导出 GLB 缺少首个 JSON 块")
        document = json.loads(stream.read(chunk_length).decode("utf-8").rstrip("\x00 \t\r\n"))

    images = document.get("images", [])
    textures = document.get("textures", [])
    materials = document.get("materials", [])
    nodes = document.get("nodes", [])
    meshes = document.get("meshes", [])
    exported_node_names = {
        node.get("name") for node in nodes if isinstance(node.get("name"), str)
    }
    expected_names = {obj.name for obj in expected_objects}
    missing_names = sorted(expected_names - exported_node_names)
    expected_mesh_count = sum(obj.type == "MESH" for obj in expected_objects)
    if missing_names:
        raise BakeError("导出 GLB 丢失低模对象: " + ", ".join(missing_names))
    if len(meshes) < expected_mesh_count:
        raise BakeError(
            f"导出 GLB 网格数量不足: 预期至少 {expected_mesh_count}，实际 {len(meshes)}"
        )
    normal_texture_indices = [
        material["normalTexture"]["index"]
        for material in materials
        if isinstance(material.get("normalTexture"), dict)
        and isinstance(material["normalTexture"].get("index"), int)
    ]
    if not images or not normal_texture_indices:
        raise BakeError("导出 GLB 中未找到法线纹理引用")
    for texture_index in normal_texture_indices:
        if texture_index < 0 or texture_index >= len(textures):
            raise BakeError("导出 GLB 的法线纹理索引无效")
        image_index = textures[texture_index].get("source")
        if not isinstance(image_index, int) or image_index < 0 or image_index >= len(images):
            raise BakeError("导出 GLB 的法线图像索引无效")
        if "bufferView" not in images[image_index] or "uri" in images[image_index]:
            raise BakeError("法线图像未以二进制数据内嵌到 GLB")
    return {
        "images": len(images),
        "textures": len(textures),
        "materials": len(materials),
        "normal_textures": len(normal_texture_indices),
        "nodes": len(nodes),
        "meshes": len(meshes),
    }


# 完成单个任务的导入、配对、检查、烘焙、原子导出和复核。
def process_task(task: BakeTask) -> BakeResult:
    started = time.perf_counter()
    result = BakeResult(
        name=task.name,
        status="failed",
        high_path=str(task.high_path),
        low_path=str(task.low_path),
        output_path=str(task.output_path),
    )
    partial_path = task.output_path.with_name(f"{task.output_path.stem}.partial.glb")
    try:
        validate_task_paths(task)
        task.output_path.parent.mkdir(parents=True, exist_ok=True)
        if partial_path.exists():
            partial_path.unlink()
        reset_scene()
        low_objects = import_glb(task.low_path)
        high_objects = import_glb(task.high_path)
        low_meshes = [obj for obj in low_objects if obj.type == "MESH"]
        high_meshes = [obj for obj in high_objects if obj.type == "MESH"]
        pairs = pair_mesh_objects(low_meshes, high_meshes)
        configure_cycles_bake(task)

        for pair in pairs:
            validate_low_mesh(pair.low)
            alignment = validate_alignment(pair, task.extrusion)
            images = bake_object(pair, task)
            result.baked_objects.append(
                {
                    "low_object": pair.low.name,
                    "image_count": len(images),
                    **alignment,
                }
            )

        export_low_glb(low_objects, partial_path)
        export_info = validate_exported_glb(partial_path, low_objects)
        os.replace(partial_path, task.output_path)
        result.baked_objects.append({"export_validation": export_info})
        result.status = "success"
    except Exception as exc:
        result.error = str(exc)
        result.details = traceback.format_exc()
        if partial_path.exists():
            try:
                partial_path.unlink()
            except OSError:
                result.warnings.append(f"未能清理临时文件: {partial_path}")
    finally:
        result.duration_seconds = round(time.perf_counter() - started, 3)
    return result


# 用临时文件替换汇总报告，避免中断时留下半段 JSON。
def write_report(report: RunReport, path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(f"{path.name}.partial")
    temporary.write_text(json.dumps(asdict(report), ensure_ascii=False, indent=2), encoding="utf-8")
    os.replace(temporary, path)


# 将清单中的相对路径统一相对清单所在目录解析。
def resolve_manifest_path(value: str, base_dir: Path) -> Path:
    path = Path(value).expanduser()
    return path if path.is_absolute() else (base_dir / path).resolve()


# 读取未来批处理所需的 JSON 清单，单任务入口与其共用同一核心。
def load_manifest(path: Path, cli_overwrite: bool) -> tuple[list[BakeTask], Path | None]:
    document = json.loads(path.read_text(encoding="utf-8"))
    if isinstance(document, list):
        defaults: dict[str, Any] = {}
        task_rows = document
        report_value = None
    elif isinstance(document, dict):
        defaults = document.get("defaults", {})
        task_rows = document.get("tasks", [])
        report_value = document.get("report")
    else:
        raise BakeError("清单根节点必须是数组或对象")
    if not isinstance(task_rows, list) or not task_rows:
        raise BakeError("清单中没有 tasks")

    base_dir = path.parent.resolve()
    tasks: list[BakeTask] = []
    for index, row in enumerate(task_rows, start=1):
        if not isinstance(row, dict):
            raise BakeError(f"清单第 {index} 项不是对象")
        merged = {**defaults, **row}
        if "high" not in merged or "low" not in merged:
            raise BakeError(f"清单第 {index} 项缺少 high 或 low")
        high_path = resolve_manifest_path(str(merged["high"]), base_dir)
        low_path = resolve_manifest_path(str(merged["low"]), base_dir)
        name = str(merged.get("name") or derive_asset_name(low_path))
        if "output" in merged:
            output_path = resolve_manifest_path(str(merged["output"]), base_dir)
        elif "output_dir" in merged:
            output_dir = resolve_manifest_path(str(merged["output_dir"]), base_dir)
            output_path = output_dir / f"{name}.glb"
        else:
            raise BakeError(f"清单第 {index} 项缺少 output 或 output_dir")
        tasks.append(
            BakeTask(
                name=name,
                high_path=high_path,
                low_path=low_path,
                output_path=output_path,
                resolution=int(merged.get("resolution", DEFAULT_RESOLUTION)),
                extrusion=float(merged.get("extrusion", DEFAULT_EXTRUSION)),
                margin=int(merged.get("margin", DEFAULT_MARGIN)),
                overwrite=bool(merged.get("overwrite", False) or cli_overwrite),
            )
        )
    report_path = resolve_manifest_path(str(report_value), base_dir) if report_value else None
    return tasks, report_path


# Blender 会把自身参数放在 -- 前，工具只解析 -- 后的独立参数。
def tool_arguments(argv: Sequence[str]) -> list[str]:
    return list(argv[argv.index("--") + 1 :]) if "--" in argv else list(argv[1:])


# 构建单组与清单两种互斥的命令行入口。
def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="将 GLB 高模法线烘焙到低模，并导出内嵌法线纹理的新 GLB。",
    )
    source = parser.add_mutually_exclusive_group(required=True)
    source.add_argument("--manifest", type=Path, help="JSON 批处理清单")
    source.add_argument("--high", type=Path, help="单任务高模 GLB")
    parser.add_argument("--low", type=Path, help="单任务低模 GLB")
    parser.add_argument("--output", type=Path, help="单任务输出 GLB")
    parser.add_argument("--output-dir", type=Path, help="单任务输出目录")
    parser.add_argument("--name", help="资产名；未填时由低模文件名推导")
    parser.add_argument("--report", type=Path, help="汇总报告 JSON 路径")
    parser.add_argument("--resolution", type=int, default=DEFAULT_RESOLUTION)
    parser.add_argument("--extrusion", type=float, default=DEFAULT_EXTRUSION)
    parser.add_argument("--margin", type=int, default=DEFAULT_MARGIN)
    parser.add_argument("--overwrite", action="store_true")
    parser.add_argument("--version", action="version", version=TOOL_VERSION)
    return parser


# 把单任务参数转换为与清单入口相同的 BakeTask。
def single_task_from_args(args: argparse.Namespace, parser: argparse.ArgumentParser) -> BakeTask:
    if args.low is None:
        parser.error("使用 --high 时必须提供 --low")
    if args.output is not None and args.output_dir is not None:
        parser.error("--output 和 --output-dir 不能同时使用")
    if args.output is None and args.output_dir is None:
        parser.error("单任务必须提供 --output 或 --output-dir")
    high_path = args.high.expanduser().resolve()
    low_path = args.low.expanduser().resolve()
    name = args.name or derive_asset_name(low_path)
    output_path = (
        args.output.expanduser().resolve()
        if args.output is not None
        else args.output_dir.expanduser().resolve() / f"{name}.glb"
    )
    return BakeTask(
        name=name,
        high_path=high_path,
        low_path=low_path,
        output_path=output_path,
        resolution=args.resolution,
        extrusion=args.extrusion,
        margin=args.margin,
        overwrite=args.overwrite,
    )


# 运行全部任务并无论成败都写出可定位到单模型的汇总报告。
def run(argv: Sequence[str]) -> int:
    parser = build_parser()
    args = parser.parse_args(tool_arguments(argv))
    if bpy is None:
        parser.error("必须由 Blender 的 Python 环境运行此工具")
    if bpy.app.version < MIN_BLENDER_VERSION:
        raise BakeError(
            f"需要 Blender {'.'.join(map(str, MIN_BLENDER_VERSION))} 或更高版本，"
            f"当前为 {bpy.app.version_string}"
        )

    if args.manifest is not None:
        manifest_path = args.manifest.expanduser().resolve()
        tasks, manifest_report = load_manifest(manifest_path, args.overwrite)
        report_path = args.report.expanduser().resolve() if args.report else manifest_report
        if report_path is None:
            report_path = manifest_path.with_name(f"{manifest_path.stem}.bake-report.json")
    else:
        tasks = [single_task_from_args(args, parser)]
        report_path = (
            args.report.expanduser().resolve()
            if args.report
            else tasks[0].output_path.with_suffix(".bake-report.json")
        )

    started_at = time.strftime("%Y-%m-%dT%H:%M:%S%z")
    report = RunReport(
        tool_version=TOOL_VERSION,
        blender_version=bpy.app.version_string,
        started_at=started_at,
    )
    for index, task in enumerate(tasks, start=1):
        print(f"[NormalBaker] ({index}/{len(tasks)}) {task.name}")
        task_result = process_task(task)
        report.results.append(task_result)
        if task_result.status == "success":
            report.success_count += 1
            print(f"[NormalBaker] SUCCESS {task.name}: {task.output_path}")
        else:
            report.failure_count += 1
            print(f"[NormalBaker] FAILED {task.name}: {task_result.error}", file=sys.stderr)
        report.finished_at = time.strftime("%Y-%m-%dT%H:%M:%S%z")
        write_report(report, report_path)

    print(
        f"[NormalBaker] DONE success={report.success_count} "
        f"failed={report.failure_count} report={report_path}"
    )
    return 0 if report.failure_count == 0 else 1


if __name__ == "__main__":
    try:
        raise SystemExit(run(sys.argv))
    except BakeError as exc:
        print(f"[NormalBaker] FATAL: {exc}", file=sys.stderr)
        raise SystemExit(2)
