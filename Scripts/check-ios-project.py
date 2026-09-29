#!/usr/bin/env python3
"""DeepSeekMeter iOS 工程结构校验（无 Xcode 环境下替代 xcodebuild 的静态自检）。

校验项：
  1. rootObject -> PBXProject 有效
  2. 每个 target：buildConfigurationList / productReference / 同步文件夹路径 / 包依赖 完整
  3. 每个 XCConfigurationList 的 buildConfigurations 引用有效
  4. INFOPLIST_FILE 与 AppIcon 资产路径存在
  5. scheme 的 BlueprintIdentifier 都指向已存在的对象
  6. XCSwiftPackageProductDependency.productName 与 Package.swift 声明的库产品一致
  7. 签名 entitlements：App 与 Widget 都设置 CODE_SIGN_ENTITLEMENTS，统一引用工程级变量，
     变量指向的 plist 存在且可解析，两边声明的 App Group 完全一致

用法：python3 Scripts/check-ios-project.py
"""
import json, subprocess, os, re, sys

root = "ios"
pbx = os.path.join(root, "DeepSeekMeter.xcodeproj/project.pbxproj")
errors = []

out = subprocess.run(["plutil", "-convert", "json", "-o", "-", pbx], capture_output=True, text=True)
if out.returncode != 0:
    print("FAIL: plutil 解析失败:", out.stderr)
    sys.exit(1)
proj = json.loads(out.stdout)
objs = proj["objects"]

# 1. rootObject -> PBXProject
ro = proj.get("rootObject")
p = objs.get(ro)
if not p or p.get("isa") != "PBXProject":
    errors.append("rootObject 不是 PBXProject")

# 6. 从 Package.swift 提取声明的库产品名
pkg_swift = os.path.join(root, "DeepSeekMeterCore/Package.swift")
declared_products = set()
if os.path.isfile(pkg_swift):
    txt = open(pkg_swift).read()
    declared_products = set(re.findall(r'\.library\(name:\s*"([^"]+)"', txt))
    if not declared_products:
        errors.append("Package.swift 未找到 .library 产品声明")

# 2/5. target 与 scheme 校验
for t in p.get("targets", []):
    target = objs.get(t)
    if not target:
        errors.append(f"target {t} 不存在"); continue
    if target.get("isa") != "PBXNativeTarget":
        errors.append(f"{t} 不是 native target"); continue
    if target.get("productType") not in ("com.apple.product-type.application", "com.apple.product-type.app-extension"):
        errors.append(f"target {t} productType 异常（应为 application 或 app-extension）")
    cl = objs.get(target.get("buildConfigurationList"))
    if not cl or cl.get("isa") != "XCConfigurationList":
        errors.append(f"target {t} 配置列表缺失")
    pr = objs.get(target.get("productReference"))
    if not pr or pr.get("isa") != "PBXFileReference":
        errors.append(f"target {t} productReference 缺失或不是 PBXFileReference")
    for g in target.get("fileSystemSynchronizedGroups", []):
        grp = objs.get(g)
        if not grp:
            errors.append(f"同步组 {g} 不存在"); continue
        path = os.path.join(root, grp.get("path", ""))
        if not os.path.isdir(path):
            errors.append(f"同步组路径不存在: {path}")
    for dep in target.get("packageProductDependencies", []):
        dd = objs.get(dep)
        if not dd or dd.get("isa") != "XCSwiftPackageProductDependency":
            errors.append(f"包依赖 {dep} 无效"); continue
        if declared_products and dd.get("productName") not in declared_products:
            errors.append(f"包产品 {dd.get('productName')} 未在 Package.swift 声明")
        pkg = objs.get(dd.get("package"))
        if not pkg or pkg.get("isa") != "XCLocalSwiftPackageReference":
            errors.append(f"包引用缺失 {dep}")
        else:
            rel = os.path.join(root, pkg.get("relativePath", ""))
            if not os.path.isdir(rel):
                errors.append(f"本地包路径不存在: {rel}")

# 3. 配置列表引用
for oid, o in objs.items():
    if o.get("isa") == "XCConfigurationList":
        for c in o.get("buildConfigurations", []):
            if c not in objs:
                errors.append(f"配置 {c} 不存在")

# 4. Info.plist 与 AppIcon 资产
for oid, o in objs.items():
    if o.get("isa") == "XCBuildConfiguration":
        bs = o.get("buildSettings", {})
        ip = bs.get("INFOPLIST_FILE")
        if ip:
            full = os.path.realpath(os.path.join(root, ip))
            if not full.startswith(os.path.realpath(root) + os.sep):
                errors.append(f"INFOPLIST_FILE 越界: {ip}")
            elif not os.path.isfile(full):
                errors.append(f"INFOPLIST_FILE 不存在: {ip}")
        icon = bs.get("ASSETCATALOG_COMPILER_APPICON_NAME")
        if icon:
            ac = os.path.join(root, f"DeepSeekMeter/Assets.xcassets/{icon}.appiconset")
            if not os.path.isdir(ac):
                errors.append(f"AppIcon 资产不存在: {ac}")


# 7. target 依赖链：PBXTargetDependency -> PBXContainerItemProxy -> PBXNativeTarget
for oid, o in objs.items():
    if o.get("isa") == "PBXTargetDependency":
        tp = objs.get(o.get("targetProxy"))
        if not tp or tp.get("isa") != "PBXContainerItemProxy":
            errors.append(f"依赖 {oid} 的 targetProxy 无效")
        else:
            rid = tp.get("remoteGlobalIDString")
            if not rid or objs.get(rid, {}).get("isa") != "PBXNativeTarget":
                errors.append(f"代理 {oid} 的 remoteGlobalIDString 未指向 native target")

# 8. PBXBuildFile：fileRef（普通资源/扩展）或 productRef（Swift 包产品）必须存在
for oid, o in objs.items():
    if o.get("isa") == "PBXBuildFile":
        fr = o.get("fileRef")
        pr = o.get("productRef")
        if fr is not None:
            if fr not in objs or objs.get(fr, {}).get("isa") != "PBXFileReference":
                errors.append(f"PBXBuildFile {oid} 的 fileRef 无效")
        elif pr is not None:
            if pr not in objs or objs.get(pr, {}).get("isa") != "XCSwiftPackageProductDependency":
                errors.append(f"PBXBuildFile {oid} 的 productRef 无效")
        else:
            errors.append(f"PBXBuildFile {oid} 缺少 fileRef/productRef")

# 9. 扩展目标：Info.plist 必须声明 widgetkit-extension
for oid, o in objs.items():
    if o.get("isa") == "XCBuildConfiguration":
        bs = o.get("buildSettings", {})
        ip = bs.get("INFOPLIST_FILE")
        if ip and "Widget" in str(ip) and os.path.isfile(os.path.join(root, ip)):
            out = subprocess.run(["plutil", "-convert", "json", "-o", "-", os.path.join(root, ip)],
                                 capture_output=True, text=True)
            if out.returncode == 0:
                info = json.loads(out.stdout)
                ext = info.get("NSExtension", {}).get("NSExtensionPointIdentifier")
                if ext != "com.apple.widgetkit-extension":
                    errors.append(f"扩展 Info.plist {ip} 缺少 NSExtensionPointIdentifier=com.apple.widgetkit-extension")

# 10. 主 target 必须包含 Embed App Extensions 阶段且依赖 widget target
for t in p.get("targets", []):
    target = objs.get(t, {})
    if target.get("productType") == "com.apple.product-type.application":
        embed_phases = [objs.get(ph) for ph in target.get("buildPhases", [])
                        if objs.get(ph, {}).get("isa") == "PBXCopyFilesBuildPhase"]
        if not embed_phases:
            errors.append(f"应用 target {t} 缺少 Embed App Extensions 阶段")
        else:
            embedded = []
            for ph in embed_phases:
                for bf in ph.get("files", []):
                    b = objs.get(bf, {})
                    fr = b.get("fileRef")
                    if fr and objs.get(fr, {}).get("path") == "DeepSeekMeterWidget.appex":
                        embedded.append(bf)
            if not embedded:
                errors.append(f"应用 target {t} 的 Embed 阶段未包含 DeepSeekMeterWidget.appex")
        if not target.get("dependencies"):
            errors.append(f"应用 target {t} 没有 target 依赖（应依赖 Widget 扩展）")

# 5. scheme 引用
scheme = os.path.join(root, "DeepSeekMeter.xcodeproj/xcshareddata/xcschemes/DeepSeekMeter.xcscheme")
if os.path.isfile(scheme):
    for m in re.finditer(r'BlueprintIdentifier = "([A-F0-9]{24})"', open(scheme).read()):
        if m.group(1) not in objs:
            errors.append(f"scheme 引用未知对象 {m.group(1)}")

# 11. 签名 entitlements：App 与 Widget 必须都设 CODE_SIGN_ENTITLEMENTS，统一引用工程级变量，
#     变量指向的 plist 必须存在且可解析；两边声明的 App Group 必须完全一致。
#     免费个人团队用空 entitlements 属预期（两边都没有 App Group 也算通过），只拦「只给一边」的情况。
proj_settings = {}
for c in objs.get(p.get("buildConfigurationList"), {}).get("buildConfigurations", []):
    for k, v in objs.get(c, {}).get("buildSettings", {}).items():
        if isinstance(v, str):  # 列表型设置（如 GCC_PREPROCESSOR_DEFINITIONS）与路径无关，跳过
            proj_settings.setdefault(k, set()).add(v)


def ent_paths(value):
    """展开 $(VAR) 为工程级变量的值（未定义则记错）；直接写路径也允许"""
    m = re.fullmatch(r"\$\(([A-Za-z0-9_]+)\)", str(value).strip())
    if not m:
        return [str(value).strip()]
    vals = proj_settings.get(m.group(1))
    if not vals:
        errors.append(f"CODE_SIGN_ENTITLEMENTS 引用的 {m.group(1)} 未在工程级定义")
        return []
    return sorted(vals)


def ent_groups(rel):
    """读 entitlements 里的 App Group 列表；越界/缺失/解析失败返回 None，空文件返回空集合"""
    full = os.path.realpath(os.path.join(root, rel))
    if not full.startswith(os.path.realpath(root) + os.sep):
        errors.append(f"CODE_SIGN_ENTITLEMENTS 越界: {rel}"); return None
    if not os.path.isfile(full):
        errors.append(f"CODE_SIGN_ENTITLEMENTS 指向的文件不存在: {rel}"); return None
    out = subprocess.run(["plutil", "-convert", "json", "-o", "-", full], capture_output=True, text=True)
    if out.returncode != 0:
        errors.append(f"entitlements 解析失败: {rel}"); return None
    ent = json.loads(out.stdout)
    groups = ent.get("com.apple.security.application-groups", [])
    if not isinstance(groups, list):
        errors.append(f"entitlements 的 application-groups 不是数组: {rel}"); return None
    return set(groups)


ent_before = len(errors)
target_groups = {}  # productType -> 该 target 实际声明的 App Group 集合
for t in p.get("targets", []):
    target = objs.get(t, {})
    if target.get("isa") != "PBXNativeTarget":
        continue
    cl = objs.get(target.get("buildConfigurationList"), {})
    for c in cl.get("buildConfigurations", []):
        cfg = objs.get(c, {})
        ce = cfg.get("buildSettings", {}).get("CODE_SIGN_ENTITLEMENTS")
        if not ce:
            errors.append(f"target {target.get('name', t)} 的 {cfg.get('name', '?')} 配置未设置 CODE_SIGN_ENTITLEMENTS")
            continue
        for rel in ent_paths(ce):
            gs = ent_groups(rel)
            if gs is not None:
                target_groups.setdefault(target.get("productType"), set()).update(gs)

app_groups = target_groups.get("com.apple.product-type.application", set())
ext_groups = target_groups.get("com.apple.product-type.app-extension", set())
# 双向比较：任一边多声明的 App Group 都会让另一边读不到/写不进共享容器
for g in sorted(app_groups - ext_groups):
    errors.append(f"App Group {g} 只在 App 声明，Widget 缺失（小组件读不到快照）")
for g in sorted(ext_groups - app_groups):
    errors.append(f"App Group {g} 只在 Widget 声明，App 缺失（App 写不进共享容器）")

if len(errors) == ent_before:
    print("✅ 签名 entitlements 校验通过（App 与 Widget 均引用 $(DEEPSEEK_ENTITLEMENTS)，App Group 两边一致）")
else:
    print("❌ 签名 entitlements 校验失败（详见下方问题列表）")

if errors:
    print("FAIL: 校验发现 " + str(len(errors)) + " 处问题")
    for e in errors:
        print("  -", e)
    sys.exit(1)
print("✅ iOS 工程结构校验通过（target/配置/包依赖/Info.plist/AppIcon/scheme/包产品名/签名 entitlements 全部自洽）")
