"""Regenerate the dependency-free Xcode project after adding/removing Swift files.
Run from any directory: python3 scripts/generate_project.py
"""
from pathlib import Path
import hashlib
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
objects = {}


def ident(key):
    return hashlib.sha256(key.encode()).hexdigest()[:24].upper()


def add(key, body):
    objects[ident(key)] = body
    return ident(key)


def array(values):
    return "(" + ", ".join(values) + ("," if values else "") + ")"


def settings(values):
    return "{ " + " ".join(f'{k} = "{v}";' for k, v in values.items()) + " }"


def configs(key, extra):
    ids = []
    for mode in ("Debug", "Release"):
        values = dict(extra)
        values.update(SWIFT_OPTIMIZATION_LEVEL="-Onone" if mode == "Debug" else "-O")
        if mode == "Debug":
            values.update(ENABLE_TESTABILITY="YES", SWIFT_ACTIVE_COMPILATION_CONDITIONS="DEBUG",
                          DEBUG_INFORMATION_FORMAT="dwarf")
        else:
            values.update(DEBUG_INFORMATION_FORMAT="dwarf-with-dsym")
        ids.append(add(f"{key}-{mode}", f'isa = XCBuildConfiguration; name = {mode}; buildSettings = {settings(values)};'))
    return add(f"{key}-config", "isa = XCConfigurationList; buildConfigurations = " + array(ids)
               + "; defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;")


targets = []
groups = []
products = []
for name, source_dir, extension, product_type in (
    ("CameraLog", "CameraLog", "app", "application"),
    ("CameraLogTests", "CameraLogTests", "xctest", "bundle.unit-test"),
):
    refs, builds = [], []
    for file in sorted((ROOT / source_dir).rglob("*.swift")):
        path = file.relative_to(ROOT).as_posix()
        ref = add(path, f'isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = "{path}"; sourceTree = SOURCE_ROOT;')
        refs.append(ref)
        builds.append(add(path + "-build", f"isa = PBXBuildFile; fileRef = {ref};"))
    groups.append(add(name + "-group", f'isa = PBXGroup; children = {array(refs)}; name = {name}; sourceTree = "<group>";'))
    product = add(name + "-product", f'isa = PBXFileReference; explicitFileType = {"wrapper.application" if extension == "app" else "wrapper.cfbundle"}; includeInIndex = 0; path = {name}.{extension}; sourceTree = BUILT_PRODUCTS_DIR;')
    products.append(product)
    phases = []
    for phase, files in (("Sources", builds), ("Frameworks", []), ("Resources", [])):
        phases.append(add(name + phase, f"isa = PBX{phase}BuildPhase; buildActionMask = 2147483647; files = {array(files)}; runOnlyForDeploymentPostprocessing = 0;"))
    values = dict(PRODUCT_NAME="$(TARGET_NAME)", PRODUCT_BUNDLE_IDENTIFIER="com.cameralog." + name.lower(),
                  GENERATE_INFOPLIST_FILE="YES", CODE_SIGN_STYLE="Automatic", SWIFT_VERSION="5.0",
                  IPHONEOS_DEPLOYMENT_TARGET="17.0", TARGETED_DEVICE_FAMILY="1,2",
                  SUPPORTED_PLATFORMS="iphoneos iphonesimulator", SDKROOT="iphoneos",
                  LD_RUNPATH_SEARCH_PATHS="$(inherited) @executable_path/Frameworks")
    dependencies = []
    if extension == "app":
        values.update(INFOPLIST_KEY_CFBundleDisplayName="CameraLog", MARKETING_VERSION="0.1.0",
                      CURRENT_PROJECT_VERSION="1", INFOPLIST_KEY_UILaunchScreen_Generation="YES",
                      INFOPLIST_KEY_UIApplicationSceneManifest_Generation="YES",
                      INFOPLIST_KEY_UISupportedInterfaceOrientations="UIInterfaceOrientationPortrait UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight",
                      INFOPLIST_KEY_LSApplicationCategoryType="public.app-category.productivity")
    else:
        values.update(TEST_HOST="$(BUILT_PRODUCTS_DIR)/CameraLog.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/CameraLog",
                      BUNDLE_LOADER="$(TEST_HOST)")
        proxy = add("test-proxy", f'isa = PBXContainerItemProxy; containerPortal = {ident("project")}; proxyType = 1; remoteGlobalIDString = {ident("CameraLog-target")}; remoteInfo = CameraLog;')
        dependencies.append(add("test-dependency", f'isa = PBXTargetDependency; target = {ident("CameraLog-target")}; targetProxy = {proxy};'))
    config = configs(name, values)
    targets.append(add(name + "-target", f'isa = PBXNativeTarget; buildConfigurationList = {config}; buildPhases = {array(phases)}; buildRules = (); dependencies = {array(dependencies)}; name = {name}; productName = {name}; productReference = {product}; productType = "com.apple.product-type.{product_type}";'))

products_group = add("products", f'isa = PBXGroup; children = {array(products)}; name = Products; sourceTree = "<group>";')
main_group = add("main-group", f'isa = PBXGroup; children = {array(groups + [products_group])}; sourceTree = "<group>";')
project_config = configs("project", dict(CLANG_ENABLE_MODULES="YES", CLANG_ENABLE_OBJC_ARC="YES",
                                         SWIFT_VERSION="5.0", IPHONEOS_DEPLOYMENT_TARGET="17.0"))
add("project", f'isa = PBXProject; attributes = {{ LastUpgradeCheck = 1600; }}; buildConfigurationList = {project_config}; compatibilityVersion = "Xcode 14.0"; developmentRegion = fr; hasScannedForEncodings = 0; knownRegions = (fr, en, Base); mainGroup = {main_group}; productRefGroup = {products_group}; projectDirPath = ""; projectRoot = ""; targets = {array(targets)};')
project_dir = ROOT / "CameraLog.xcodeproj"
project_dir.mkdir(exist_ok=True)
body = "\n".join(f"\t\t{key} = {{ {value} }};" for key, value in objects.items())
(project_dir / "project.pbxproj").write_text(
    '// !$*UTF8*$!\n{\n\tarchiveVersion = 1;\n\tclasses = {};\n\tobjectVersion = 56;\n\tobjects = {\n'
    + body + f'\n\t}};\n\trootObject = {ident("project")};\n}}\n', encoding="utf-8")

scheme = ET.Element("Scheme", LastUpgradeVersion="1600", version="1.3")


def reference(parent, name, extension):
    ET.SubElement(parent, "BuildableReference", BuildableIdentifier="primary",
                  BlueprintIdentifier=ident(name + "-target"), BuildableName=name + "." + extension,
                  BlueprintName=name, ReferencedContainer="container:CameraLog.xcodeproj")


build = ET.SubElement(scheme, "BuildAction", parallelizeBuildables="YES", buildImplicitDependencies="YES")
entries = ET.SubElement(build, "BuildActionEntries")
entry = ET.SubElement(entries, "BuildActionEntry", buildForTesting="YES", buildForRunning="YES",
                      buildForProfiling="YES", buildForArchiving="YES", buildForAnalyzing="YES")
reference(entry, "CameraLog", "app")
test = ET.SubElement(scheme, "TestAction", buildConfiguration="Debug",
                     selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB",
                     selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB", shouldUseLaunchSchemeArgsEnv="YES")
testable = ET.SubElement(ET.SubElement(test, "Testables"), "TestableReference", skipped="NO")
reference(testable, "CameraLogTests", "xctest")
launch = ET.SubElement(scheme, "LaunchAction", buildConfiguration="Debug",
                       selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB",
                       selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB", launchStyle="0",
                       useCustomWorkingDirectory="NO", ignoresPersistentStateOnLaunch="NO",
                       debugDocumentVersioning="YES", debugServiceExtension="internal", allowLocationSimulation="YES")
reference(ET.SubElement(launch, "BuildableProductRunnable", runnableDebuggingMode="0"), "CameraLog", "app")
profile = ET.SubElement(scheme, "ProfileAction", buildConfiguration="Release", shouldUseLaunchSchemeArgsEnv="YES",
                        savedToolIdentifier="", useCustomWorkingDirectory="NO", debugDocumentVersioning="YES")
reference(ET.SubElement(profile, "BuildableProductRunnable", runnableDebuggingMode="0"), "CameraLog", "app")
ET.SubElement(scheme, "AnalyzeAction", buildConfiguration="Debug")
ET.SubElement(scheme, "ArchiveAction", buildConfiguration="Release", revealArchiveInOrganizer="YES")
scheme_dir = project_dir / "xcshareddata" / "xcschemes"
scheme_dir.mkdir(parents=True, exist_ok=True)
ET.indent(scheme)
ET.ElementTree(scheme).write(scheme_dir / "CameraLog.xcscheme", encoding="utf-8", xml_declaration=True)
print(f"Generated {len(objects)} Xcode objects, {len(targets)} targets.")
