{ Unleashed Pascal Installer - (c) 2026 Unleashed Pascal. See LICENSE. }

unit install_pipeline;

{$mode unleashed}

interface

uses
  Classes, SysUtils;

type
  TStringArray = array of string;

  TInstallConfig = record
    InstallFpc:     Boolean;
    InstallLazarus: Boolean;
    FpcLatest:      Boolean;
    FpcBranch:      string;
    FpcHash:        string;
    LazLatest:      Boolean;
    LazBranch:      string;
    LazHash:        string;
    TargetDir:      string;
    CrossWin64:     Boolean;     // only meaningful on Linux host
    CrossWin32:     Boolean;     // legacy
    CrossLinux64:   Boolean;     // only meaningful on Windows host
    CrossLinux32:   Boolean;     // legacy
    CrossWasm:      Boolean;
    // optional Lazarus IDE addons. Each is independent; toggling one off
    // means we skip --add-package for it. lazbuild --build-ide picks up
    // whatever's in <pcp>/staticpackages.inc and links it via the
    // {$IFDEF AddStaticPkgs} block in lazarus.pp, so no source patching
    // is needed -- the lazarus packagesystem.pas:2533 sets that define
    // automatically when building the IDE.
    InstallMinimap: Boolean;
    // Unleashed minimap: the fork's own source-editor map, unrelated to
    // the stock lazminimap above. Both can be registered at once, so the
    // two checkboxes are independent.
    InstallUnleashedMinimap: Boolean;
    // CPU-View IDE plugin (instructions/registers/stack views) with its
    // FWHexView runtime dependency. Both packages travel together as a
    // single user-facing checkbox; pipeline registers FWHexView.LCL +
    // FWHexView_D.LCL + the host-platform CPUView_<plat>_D.lpk.
    InstallCPUView: Boolean;
    // ToggleDisplayAffinity IDE plugin: adds a Window menu entry that
    // flips SetWindowDisplayAffinity on the IDE main window, so screen-
    // capture / screen-share tools omit the editor. The plugin source
    // gates its actual logic with {$ifdef WINDOWS}; on Linux it compiles
    // to an empty Register procedure. The UI surfaces it as a disabled
    // checkbox on Linux hosts to make the platform restriction obvious.
    InstallToggleAffinity: Boolean;
    // MetaDarkStyle IDE theme: cross-platform dark color scheme for the
    // Lazarus IDE. Runtime package (MetaDarkStyle.lpk) gets registered
    // link-only as a dependency of the design-time piece
    // (metadarkstyledsgn.lpk) which carries the IDE integration.
    InstallMetaDarkStyle: Boolean;
    // CHM documentation bundle (~31 MB) into <lazarus>\docs\chm. Without
    // it F1 finds the viewer but has nothing to show. Not an IDE package:
    // no lazbuild involved, just download + extract.
    InstallHelpFiles: Boolean;
    // user-side preference; pipeline only persists it to manifest so
    // the next install run can restore the checkbox state.
    LaunchAfter: Boolean;
    // IDE launch shortcuts. UI requires at least one when InstallLazarus
    // is on -- the shortcut carries --pcp, the only correct way to start
    // the IDE (raw binary spills config + breaks the docked layout).
    MakeDesktopShortcut: Boolean;
    MakeFolderShortcut:  Boolean;
    // SHA we resolved at the UI layer (head of chosen branch or
    // user-provided hash). pipeline writes this into the manifest at
    // end of install so a later run can decide whether to refresh.
    FpcSelectedSha: string;
    LazSelectedSha: string;
    // when True, pipeline appends every Log() line to
    // <TargetDir>\installer.log (truncated at start of each run).
    SaveLog: Boolean;
  end;

  TInstallLogEvent      = procedure(const msg: string) of object;
  TInstallProgressEvent = procedure(Percent: Integer; const status: string) of object;

  // pipeline stages, ordered. each gets a slice of the 0..100 overall
  // bar via STAGE_END below. boundaries are tuned to typical wall-clock
  // proportions: build steps dominate, downloads + cfg are short.
  TInstallStage = (
    isInit,
    isCleanPrev,        //  0..5    verbose removal of previous build trees (update)
    isBootstrap,        //  5..8    download + extract bootstrap zip
    isFpcSrc,           //  8..14   download + extract fpc source
    isFpcMakeAll,       // 14..40   make all (~5-10 min)
    isFpcMakeUtils,     // 40..44   make utils
    isFpcMakeInstall,   // 44..48   make install
    isFpcCfg,           // 48..49   fpcmkcfg (must run before any cross
                        //          step so Linux cross can patch fpc.cfg)
    isFpcCross,         // 49..63   crossinstall i386-win32 (~3-5 min)
    isFpcCrossWasm,     // 63..65   crossinstall wasm32-wasip1 (~2 min)
    isFpcCrossLinux64,  // 65..71   crossinstall x86_64-linux (~5-10 min)
    isFpcCrossLinux32,  // 71..77   crossinstall i386-linux (~5-10 min)
    isLazSrc,           // 77..80   download + extract lazarus
    isLazMakelazbuild,  // 80..84   make lazbuild prereqs
    isLazComponents,    // 84..85   download + extract optional addon zips
    isLazPackages,      // 85..89   N x lazbuild --add-package
    isLazIde,           // 89..96   lazbuild --build-ide
    isLazConfig,        // 96..97   write env opts + ack files
    isHelp,             // 97..98   lhelp viewer build + CHM docs
    isShortcut,         // 98..99   desktop shortcut
    isDone);            // 100

  TInstallThread = class(TThread)
  private
    FCfg: TInstallConfig;
    FOnLog: TInstallLogEvent;
    FOnProgress: TInstallProgressEvent;
    FSuccess: Boolean;
    FErrorMsg: string;
    FStage: TInstallStage;
    // marshalled fields (thread writes, main reads in Sync*)
    FLogMsg: string;
    FProgressMsg: string;
    FProgressPct: Integer;
    // optional installer.log writer; nil when save-log is off. owned
    // and freed inside Execute so lifetime is exactly the pipeline run.
    FLogStream: TFileStream;
    // diagnostic: dump child-env / make-resolution once per pipeline run
    // (Linux-only -- helps trace make wrappers + stray MAKEFLAGS leaks)
    FLoggedMakeDiag: Boolean;
    // cache for detected fpc version (linux only; freshly-built unleashed
    // can be a different version than the 3.2.2 bootstrap, so we scan
    // lib/fpc/<ver>/ at runtime instead of hardcoding it)
    FHostFpcVersion: string;
    procedure SyncLog;
    procedure SyncProgress;
    procedure Log(const msg: string);
    procedure Progress(Percent: Integer; const status: string);
    procedure SetStage(s: TInstallStage);
    procedure OnMakeLine(const Line: string);
    function ResolveLogPath: string;
    procedure logHostFpcEnv;
    function makeCfgOpt: string;
    function StepBootstrap: Boolean;
    function StepDownloadFpcSource: Boolean;
    function StepBuildFpcNative: Boolean;
    function StepBuildFpcCross: Boolean;
{$ifdef WINDOWS}
    function stepStageWin64Binutils: Boolean;
{$endif}
    function stepStageWin32Binutils(add: Boolean): Boolean;
    function StepRemoveCrossWin32: Boolean;
    function StepBuildFpcCrossWasm: Boolean;
    function StepRemoveCrossWasm: Boolean;
    function StepBuildFpcCrossLinux64: Boolean;
    function StepRemoveCrossLinux64: Boolean;
    function StepBuildFpcCrossLinux32: Boolean;
    function StepRemoveCrossLinux32: Boolean;
    function StepBuildFpcCrossWin64FromLinux: Boolean;
    function StepRemoveCrossWin64FromLinux: Boolean;
    function StepBuildFpcCrossWin32FromLinux: Boolean;
    function StepRemoveCrossWin32FromLinux: Boolean;
    function StepBuildFpcCrossLinux32FromLinux: Boolean;
    function StepRemoveCrossLinux32FromLinux: Boolean;
    function DownloadAndVerify(const Url, Sha, DestZip, StepLabel: string): Boolean;
    function UnpackLinuxCross(const Tag, BinUrl, BinSha, LibUrl, LibSha, BinDir, LibDir: string): Boolean;
    function LinuxCommonMakeArgs(const TargetCpu, BinDir, LibDir, BinPrefix: string): TStringArray;
    function PatchFpcCfgCrossSection(const TargetOs, TargetCpu, BinDir, LibDir, BinPrefix: string; Add: Boolean): Boolean;
    procedure StepM3Cleanup;
    function StepGenerateFpcCfg: Boolean;
    function StepDownloadComponents: Boolean;
    function StepRebuildLazarusForAddons: Boolean;
    procedure UnregisterIdePackage(const PkgName: string);
    function StepDownloadLazarusSource: Boolean;
    function StepBuildLazarus: Boolean;
    function stepBuildLHelp: Boolean;
    function stepInstallHelpFiles: Boolean;
    procedure runHelpSteps;
    function StepGenerateLazarusConfig: Boolean;
    function StepCreateShortcuts: Boolean;
    function ResolveLazarusRef: string;
    function LazarusDir: string;
    function LazarusPcp: string;
    function ComponentsExtraDir: string;
    function RunLazbuild(const Args: array of string;
      const StepLabel: string): Boolean;
    function AddPackage(const LpkRel: string; LinkOnly: Boolean = False): Boolean;
    function AddPackageAbs(const LpkAbs: string; LinkOnly: Boolean = False): Boolean;
    function RegisterCPUViewPackages: Boolean;
    procedure UnregisterCPUViewPackages;
    procedure RegisterCPUViewToolbarButton;
    procedure UnregisterCPUViewToolbarButton;
    function RegisterMetaDarkStylePackages: Boolean;
    procedure WriteMinimapConfig;
    procedure UnregisterMetaDarkStylePackages;
    function WriteConfigFile(const FilePath, Content: string): Boolean;
    function ResolveFpcRef: string;
    function MakeWorkDir: string;
    function BootstrapBinDir: string;
    function HostFpcBinDir: string;     // <target>/<HostFpcBinSubdir>/
    function HostFpcUtilDir: string;    // <target>/<HostFpcUtilSubdir>/
    function HostFpcUnitsDir: string;   // <target>/.../units/  -- RTL+packages
    function HostFpcVersion: string;    // detected dir name under lib/fpc/
    procedure RemoveDir(const Path: string);
    procedure removeDirVerbose(const path: string; pctFrom, pctTo: Integer);
    procedure EnsureCompilerSymlinks;
    procedure InstallFpcWrapper;
    function RunMake(const Args: array of string;
      const StepLabel: string): Boolean;
  protected
    procedure Execute; override;
  public
    constructor Create(const Cfg: TInstallConfig;
      ALog: TInstallLogEvent; AProgress: TInstallProgressEvent;
      AOnTerminate: TNotifyEvent);
    property Success: Boolean read FSuccess;
    property ErrorMsg: string read FErrorMsg;
  end;

const
{$ifdef WINDOWS}
  // portable extract of fpc-3.2.2.i386-win32.exe (Inno Setup), unpacked
  // off-line to skip registry, PATH, file association, shortcut side effects.
  // ppc386.exe (FPC 3.2.2, i386-win32 native) bootstraps the unleashed
  // compiler. Earlier we tried switching to the win32+win64 combo bundle
  // and bootstrapping with ppcrossx64.exe -- on this host's FPC version
  // that breaks `make all` for the native target with 'Cannot open
  // include file x86_64.inc'. The i386-only bootstrap is the one the
  // diagnostic scripts proved to work end-to-end.
  BOOTSTRAP_URL =
    'https://github.com/unleashedpascal/compiler/releases/download/bootstrappers-v1/fpc-3.2.2-i386-win32-portable.zip';
  BOOTSTRAP_SHA =
    '0DFB6E34EC1FB1E89B5EAEA90E3A514B1F37867AE91989FA18143750EB39BF30';
{$endif}
{$ifdef LINUX}
  // portable extract of the upstream fpc-3.2.2.x86_64-linux.tar (the
  // cross-distro tarball; install.sh-style prefix, not .deb/.rpm).
  // Repacked as ZIP so the same TUnZipper path handles both host OSes;
  // Linux unix exec bits are lost during zipping, the pipeline must
  // restore +x on bin/* and lib/fpc/3.2.2/ppc* after extract.
  // Layout inside the zip (no wrapper dir): bin/, lib/, man/, share/.
  BOOTSTRAP_URL =
    'https://github.com/unleashedpascal/compiler/releases/download/bootstrappers-v1/fpc-3.2.2-x86_64-linux-portable.zip';
  BOOTSTRAP_SHA =
    'C6072EE3E47DB6280E16347BAF4B2637B3A09FC2AB8D14B50F69C06579F55B02';
{$endif}

  // Filename portion of the bootstrap zip (used for the local download path).
{$ifdef WINDOWS}
  BOOTSTRAP_ZIP_NAME = 'fpc-3.2.2-i386-win32-portable.zip';
{$endif}
{$ifdef LINUX}
  BOOTSTRAP_ZIP_NAME = 'fpc-3.2.2-x86_64-linux-portable.zip';
{$endif}

  // Host-OS plumbing constants. Sub-paths use literal '\' on Windows and '/'
  // on Linux because they end up concatenated with TargetDir which is in
  // the platform's native separator already (TSelectDirectoryDialog returns
  // either form).
{$ifdef WINDOWS}
  ExeExt              = '.exe';
  HostTargetOs        = 'win64';      // -> make OS_TARGET=
  // bootstrap zip lays out portable FPC 3.2.2 i386-win32 with ppc386.exe +
  // make.exe + binutils all in this one subdir.
  BootstrapBinSubdir  = 'fpc322\bin\i386-win32';
  BootstrapPpName     = 'ppc386';     // + ExeExt
  // host fpc post-`make install`: everything (ppcx64, ppcross*, fpcmkcfg,
  // fpc.cfg, fpc wrapper) ends up flat in one bin\<host-target>\ dir.
  HostFpcBinSubdir    = 'fpc\bin\x86_64-win64';
  HostFpcUtilSubdir   = 'fpc\bin\x86_64-win64';   // same as compiler dir on Win
{$endif}
{$ifdef LINUX}
  ExeExt              = '';
  HostTargetOs        = 'linux';
  // upstream fpc-3.2.2.x86_64-linux portable zip layout: ppcx64 lives in
  // lib/fpc/3.2.2/, bin/ holds shell-script wrappers + fpcmkcfg etc.
  BootstrapBinSubdir  = 'fpc322/lib/fpc/3.2.2';
  BootstrapPpName     = 'ppcx64';
  // host fpc post-`make install` on Linux follows standard unix prefix:
  //   <prefix>/bin/{fpc,fpcmkcfg,...}        wrappers + utilities
  //   <prefix>/lib/fpc/3.2.2/ppcx64          compiler binary (and ppcross*)
  //   <prefix>/lib/fpc/3.2.2/units/<tgt>/    RTL units
  //   <prefix>/lib/fpc/3.2.2/fpc.cfg         config (placed by fpcmkcfg)
  HostFpcBinSubdir    = 'fpc/lib/fpc/3.2.2';
  HostFpcUtilSubdir   = 'fpc/bin';
{$endif}

{$ifdef WINDOWS}
  // native x86_64-win64 binutils (from FPC's own fpcbuild install/binw64,
  // statically linked). The default internal assembler+linker never needs
  // them, but -a/-al/-as/-Xe switch to external assembling and expect
  // as.exe next to the compiler; same layout as the upstream installer.
  BINW64_URL =
    'https://github.com/unleashedpascal/compiler/releases/download/bootstrappers-v1/binutils-2.28-x86_64-win64.zip';
  BINW64_SHA =
    'AE7C0D747C55EBB1760F8B4304BFA89BE78151594F5A21B5612DE252FE879E5A';
{$endif}

  // codeload accepts branch name, tag, full or short SHA in <ref>
  FPC_SOURCE_URL_PREFIX =
    'https://codeload.github.com/unleashedpascal/compiler/zip/';
  LAZARUS_SOURCE_URL_PREFIX =
    'https://codeload.github.com/unleashedpascal/ide/zip/';

  // Cross-toolchain mirrors hosted on the FPC bootstrap release.
  // _BIN: cross-binutils (Win32 PE producing Linux ELF). _LIB: glibc
  // runtime + Ubuntu 18.04 shared objects for full LCL widget-set.
  CROSS_LINUX64_BIN_URL =
    'https://github.com/unleashedpascal/compiler/releases/download/bootstrappers-v1/Linux_AMD64_Linux_V241.zip';
  CROSS_LINUX64_BIN_SHA =
    'BE7F575C4383C98F4A14D22CD939C58C9D8A458B8E3FC2125348ECA5E9826733';
  CROSS_LINUX64_LIB_URL =
    'https://github.com/unleashedpascal/compiler/releases/download/bootstrappers-v1/Linux_AMD64_Ubuntu_1804.zip';
  CROSS_LINUX64_LIB_SHA =
    '674B1CB4A21E0CE7000B848CB75E201CD2E317C8E71833C76D9EAD05FD7DF221';
  CROSS_LINUX32_BIN_URL =
    'https://github.com/unleashedpascal/compiler/releases/download/bootstrappers-v1/Linux_i386_Linux_V241.zip';
  CROSS_LINUX32_BIN_SHA =
    '119459D71FB54ECBA5760BDE0D96AA4455C16C7AC9A5F8CC3E2C0CC02B8E48E3';
  CROSS_LINUX32_LIB_URL =
    'https://github.com/unleashedpascal/compiler/releases/download/bootstrappers-v1/Linux_i386_Ubuntu_1804.zip';
  CROSS_LINUX32_LIB_SHA =
    'A09F3168FFCBBF21AD15A3FD0A6A88C0DD4123FA6FF47B18C63701A7A05728EA';

  // Optional Lazarus IDE add-on packages distributed in a separate
  // components-v1 release. Two upstream projects shipped here:
  //   FWHexView 2.0.16 -- cross-platform HEX viewer (MIT)
  //   CPUView 1.0      -- debugger plugin (MIT), depends on FWHexView.LCL
  // Each download lands as a zip in TargetDir/components_extra/ and is
  // extracted in place. Sources only -- lazbuild rebuilds .lpk into
  // .ppu against the freshly-built host RTL.
  COMPONENTS_FWHEX_URL =
    'https://github.com/unleashedpascal/compiler/releases/download/components-v1/FWHexView_2.0.16.zip';
  COMPONENTS_FWHEX_SHA =
    'B6CDF3A768811F557AA17C45A6F321FEBF0419B3280FA6EEE3BBBE2BB515D3F8';
  COMPONENTS_CPUVIEW_URL =
    'https://github.com/unleashedpascal/compiler/releases/download/components-v1/CPUView_1.0_20260711_8fa24fa.zip';
  COMPONENTS_CPUVIEW_SHA =
    '890C80E4C031D588B3E93BEAB9F850FCB4D840E154F8CFE123531D1395887F7B';
  // ToggleDisplayAffinity 1.0 design-time IDE plugin (Windows-only logic;
  // package compiles to no-op on other hosts). Single .lpk, no runtime
  // dependency split. Only fetched + registered when the user ticks the
  // Toggle Display Affinity checkbox on a Windows host.
  COMPONENTS_TOGGLE_URL =
    'https://github.com/unleashedpascal/compiler/releases/download/components-v1/ToggleDisplayAffinity.zip';
  COMPONENTS_TOGGLE_SHA =
    '7EA739C994FD725FBD30EFBE216DD97732A64BC26D41EB53B03759441DB80E1E';
  // MetaDarkStyle 0.9 dark IDE theme. Cross-platform (LCL-based). Ships
  // a runtime .lpk (MetaDarkStyle.lpk -- the actual dark-mode logic) and
  // a design-time .lpk (metadarkstyledsgn.lpk -- the IDE plugin that
  // exposes the theme through Tools -> Options). Both are LGPL; the
  // dsgn package pulls the runtime in via RequiredPkgs so registration
  // order matters: link-only the runtime first, then the design-time.
  // Lazarus CHM documentation bundle: rtl/fcl/lcl/lazutils/prog/ref/user
  // .chm plus the .xct cross-reference files lhelp needs to jump between
  // them. Zip has a single top-level chm/ dir, so it extracts straight
  // into <lazarus>\docs\. Mirrored from the upstream SourceForge release
  // because that link redirects through rotating mirrors, which makes the
  // payload unpinnable and lets an error page arrive as a 200.
  DOCS_CHM_URL =
    'https://github.com/unleashedpascal/compiler/releases/download/components-v1/doc-chm-fpc3.2.4-laz4.8-0.zip';
  DOCS_CHM_SHA =
    'E48DEA99C5AF62D3D1746479739F6A53874D726577203802550D90B24B013884';

  COMPONENTS_METADARK_URL =
    'https://github.com/unleashedpascal/compiler/releases/download/components-v1/MetaDarkStyle_0.9.zip';
  COMPONENTS_METADARK_SHA =
    '1E889E0B0C8BF49703C728C39F92C114B67E963B8226D46B2120696C99EED536';

implementation

uses
  XMLConf, download_util, hash_util, zip_util, proc_util, shortcut_util, install_manifest;

{$ifdef LINUX}
// libc's setenv (FPC's BaseUnix doesn't surface fpsetenv in all 3.x versions;
// declaring the libc symbol directly is the most portable route).
// overwrite=1 -> replace any prior value, matching POSIX setenv contract.
function c_setenv(name, value: PChar; overwrite: LongInt): LongInt; cdecl;
  external 'c' name 'setenv';
{$endif}

const
  // upper bound (on 0..100) of each stage's overall-progress slice.
  // index 0 (isInit) is implicitly 0; subsequent values are the cap.
  STAGE_END: array[TInstallStage] of Byte = (
    0,    // isInit
    5,    // isCleanPrev
    8,    // isBootstrap
    14,   // isFpcSrc
    40,   // isFpcMakeAll
    44,   // isFpcMakeUtils
    48,   // isFpcMakeInstall
    49,   // isFpcCfg
    63,   // isFpcCross
    65,   // isFpcCrossWasm
    71,   // isFpcCrossLinux64
    77,   // isFpcCrossLinux32
    80,   // isLazSrc
    84,   // isLazMakelazbuild
    85,   // isLazComponents
    89,   // isLazPackages
    96,   // isLazIde
    97,   // isLazConfig
    98,   // isHelp
    99,   // isShortcut
    100); // isDone

  STAGE_NAME: array[TInstallStage] of string = (
    'init', 'cleaning previous build', 'bootstrap FPC 3.2.2', 'unleashed-pascal source', 'building native compiler', 'building utils', 'installing compiler', 'fpc.cfg', 'building i386 cross compiler',
    'building wasm cross compiler', 'building x86_64-linux cross compiler', 'building i386-linux cross compiler', 'ide source',
    'building lazbuild + LCL', 'fetching addon components', 'registering IDE packages', 'building IDE', 'writing IDE config', 'help', 'desktop shortcut', 'done');

const
  // baked minimal Lazarus environmentoptions.xml. Version 112 / Lazarus
  // 4.99 matches the current main of unleashedpascal/ide.
  // ActiveDesktop="default docked" makes the IDE start in single-window
  // dock layout (anchordockingdsgn handles the runtime when the package
  // is installed - which we do via lazbuild --add-package).
  // InitialFPCSrcRescanDone skips the slow first-launch scan over <fpcsrc>.
  ENV_OPTIONS_TEMPLATE: string =
    '<?xml version="1.0" encoding="UTF-8"?>'#13#10 +
    '<CONFIG>'#13#10 +
    '  <EnvironmentOptions>'#13#10 +
    '    <Version Lazarus="4.99" Value="112"/>'#13#10 +
    '    <Language ID="en"/>'#13#10 +
    '    <LazarusDirectory Value="%LAZ%"/>'#13#10 +
    '    <CompilerFilename Value="%FPC%"/>'#13#10 +
    '    <FPCSourceDirectory Value="%FPCSRC%"/>'#13#10 +
    '    <MakeFilename Value="%MAKE%"/>'#13#10 +
    '    <TestBuildDirectory Value="%PROJECTS%"/>'#13#10 +
    '    <InitialFPCSrcRescanDone Value="True"/>'#13#10 +
    '  </EnvironmentOptions>'#13#10 +
    // explicit Desktop1 + Desktop2 so the IDE has named entries to
    // activate; DockMaster ties Desktop2 to anchordocking. layout
    // details (window positions etc.) are filled in on first save.
    '  <Desktops Count="2" ActiveDesktop="default docked">'#13#10 +
    '    <Desktop1 Name="default"/>'#13#10 +
    '    <Desktop2 Name="default docked" DockMaster="TIDEAnchorDockMaster"/>'#13#10 +
    '  </Desktops>'#13#10 +
    '</CONFIG>'#13#10;

  // pre-acknowledge the "Enable anchor docking?" prompt. without this
  // the IDE shows a blocking dialog on first run.
  ANCHOR_DOCKING_OPTIONS: string =
    '<?xml version="1.0" encoding="UTF-8"?>'#13#10 +
    '<CONFIG>'#13#10 +
    '  <DoneAskUserEnableAnchorDock Value="True"/>'#13#10 +
    '</CONFIG>'#13#10;

  // pre-acknowledge the "Enable docked form designer?" prompt.
  DOCKED_FORM_EDITOR_OPTIONS: string =
    '<?xml version="1.0" encoding="UTF-8"?>'#13#10 +
    '<CONFIG>'#13#10 +
    '  <DoneAskUserEnableDockedDesigner Value="True"/>'#13#10 +
    '</CONFIG>'#13#10;

  // FpDebug is the user fork's preferred backend (modern, internal, no
  // external gdb.exe required). without this file the IDE pops the
  // "Configure Lazarus IDE" wizard on first launch with a red "!" on
  // the Debugger tab. UID is a fixed GUID matching unleashed21's
  // reference install.
  DEBUGGER_OPTIONS: string =
    '<?xml version="1.0" encoding="UTF-8"?>'#13#10 +
    '<CONFIG>'#13#10 +
    '  <Debugger Version="1">'#13#10 +
    '    <Backends Version="1">'#13#10 +
    '      <Config ConfigName="FpDebug" ConfigClass="TFpDebugDebugger" Active="True" UID="{65D78958-7ADA-40EE-B528-5FFCB08E4544}"/>'#13#10 +
    '    </Backends>'#13#10 +
    '  </Debugger>'#13#10 +
    '</CONFIG>'#13#10;

  // Editor defaults that differ from stock Lazarus. mbaSelectColumn puts
  // block selection on the middle mouse button (stock: paste). Written
  // only when the file is absent so a re-install keeps the user's fonts
  // and colour scheme.
  EDITOR_OPTIONS: string =
    '<?xml version="1.0" encoding="UTF-8"?>'#13#10 +
    '<CONFIG>'#13#10 +
    '  <EditorOptions Version="13">'#13#10 +
    '    <Misc MultiCaretOnColumnSelect="True"/>'#13#10 +
    '    <Mouse>'#13#10 +
    '      <Default Version="1" TextMiddleClick="mbaSelectColumn"/>'#13#10 +
    '    </Mouse>'#13#10 +
    '  </EditorOptions>'#13#10 +
    '</CONFIG>'#13#10;

constructor TInstallThread.Create(const Cfg: TInstallConfig;
  ALog: TInstallLogEvent; AProgress: TInstallProgressEvent;
  AOnTerminate: TNotifyEvent);
begin
  inherited Create(True);
  FCfg := Cfg;
  FOnLog := ALog;
  FOnProgress := AProgress;
  FreeOnTerminate := True;
  OnTerminate := AOnTerminate;
  Start;
end;

procedure TInstallThread.SyncLog;
begin
  if Assigned(FOnLog) then FOnLog(FLogMsg);
end;

procedure TInstallThread.SyncProgress;
begin
  if Assigned(FOnProgress) then FOnProgress(FProgressPct, FProgressMsg);
end;

procedure TInstallThread.Log(const msg: string);
begin
  if FLogStream <> nil then begin
    var line: AnsiString := AnsiString(FormatDateTime('hh:nn:ss', Now) + '# ' + msg + LineEnding);
    if Length(line) > 0 then
      FLogStream.WriteBuffer(line[1], Length(line));
  end;
  FLogMsg := msg;
  Synchronize(@SyncLog);
end;

// Percent is the LOCAL pct of the current stage (0..100), or -1 for marquee.
// remap to overall via STAGE_END before sending to UI so the bar climbs
// monotonically across the whole install.
procedure TInstallThread.Progress(Percent: Integer; const status: string);
begin
  var rangeStart := if FStage = isInit then 0 else STAGE_END[Pred(FStage)];
  var rangeEnd   := STAGE_END[FStage];
  if Percent < 0 then
    FProgressPct := -1
  else
  begin
    if Percent > 100 then Percent := 100;
    FProgressPct := rangeStart + Round((rangeEnd - rangeStart) * Percent / 100);
  end;
  FProgressMsg := STAGE_NAME[FStage] + ': ' + status;
  Synchronize(@SyncProgress);
end;

procedure TInstallThread.SetStage(s: TInstallStage);
begin
  FStage := s;
  // entering stage: park bar at this stage's start (= prev stage end);
  // status text shows the stage name only until sub-progress arrives
  Progress(0, '...');
end;

// installer.log lives in the install dir alongside installer.ini so a
// user inspecting the install has everything in one place. truncated
// each run (fmCreate in Execute).
function TInstallThread.ResolveLogPath: string;
begin
  Result := IncludeTrailingPathDelimiter(FCfg.TargetDir) + 'installer.log';
end;

// pull "[ NN%]" out of a lazbuild --build-ide line (or any line that
// uses that progress format) and feed it into the current stage's
// progress bar. returns False if no usable percent was found.
function ExtractLazbuildPercent(const Line: string; out Pct: Integer): Boolean;
begin
  Result := False;
  var pOpen := Pos('[', Line);
  if pOpen = 0 then Exit;
  var pClose := Pos('%]', Line);
  if (pClose = 0) or (pClose < pOpen) then Exit;
  Pct := StrToIntDef(Trim(Copy(Line, pOpen + 1, pClose - pOpen - 1)), -1);
  Result := (Pct >= 0) and (Pct <= 100);
end;

procedure TInstallThread.OnMakeLine(const Line: string);
begin
  // make + fpc are loud. drop the two lowest-severity diagnostics
  // (Hint and Note) to keep the user-visible log readable; Warning
  // and above still come through, plus structural lines (Compiling,
  // Linking, make[n]: Entering, ...).
  if Pos('Hint:', Line) > 0 then Exit;
  if Pos('Note:', Line) > 0 then Exit;
  Log(Line);
  // lazbuild's --build-ide emits "[ NN%] ..." every package; map that
  // straight into the current stage's progress slice
  var Pct: Integer;
  if ExtractLazbuildPercent(Line, Pct) then
    Progress(Pct, Trim(Copy(Line, Pos('%]', Line) + 2, MaxInt)));
end;

function TInstallThread.ResolveFpcRef: string;
begin
  Result := if (not FCfg.FpcLatest) and (FCfg.FpcHash <> '') then FCfg.FpcHash
            else FCfg.FpcBranch;
end;

function TInstallThread.MakeWorkDir: string;
begin
  // FPC source tree lives at <install>\fpcsrc - flat, sibling of fpc/
  // and lazarus/. Both make targets and the lazarus IDE config point
  // at this path.
  Result := IncludeTrailingPathDelimiter(FCfg.TargetDir) + 'fpcsrc';
end;

function TInstallThread.BootstrapBinDir: string;
begin
  Result := IncludeTrailingPathDelimiter(FCfg.TargetDir) + BootstrapBinSubdir;
end;

// Linux-only: scan <install>/fpc/lib/fpc/ for a version-like subdir
// (e.g. "3.2.2", "3.3.1") that contains a ppcx64 binary. Unleashed Pascal
// is currently 3.3.1 while the bootstrap is 3.2.2; we can't hardcode
// the version because the source tree decides it (FPC_VERSION in
// fpcdefs.inc). Result cached after first successful detection.
function TInstallThread.HostFpcVersion: string;
begin
  if FHostFpcVersion <> '' then Exit(FHostFpcVersion);
{$ifdef LINUX}
  var Base := IncludeTrailingPathDelimiter(FCfg.TargetDir) + 'fpc/lib/fpc';
  if DirectoryExists(Base) then begin
    var SR: TSearchRec;
    if FindFirst(IncludeTrailingPathDelimiter(Base) + '*', faDirectory, SR) = 0 then
    try
      repeat
        if (SR.Name <> '.') and (SR.Name <> '..') and ((SR.Attr and faDirectory) <> 0) and (Length(SR.Name) > 0) and (SR.Name[1] in ['0'..'9']) and
           FileExists(IncludeTrailingPathDelimiter(Base) + SR.Name + '/ppcx64') then begin
          FHostFpcVersion := SR.Name;
          Break;
        end;
      until FindNext(SR) <> 0;
    finally
      FindClose(SR);
    end;
  end;
{$endif}
  // Pre-install fallback: matches the bootstrap so paths log sensibly
  // until make install lands the real version on disk. Real callers
  // (HostFpcBinDir et al.) invoke us after make install, so they get
  // the detected value.
  if FHostFpcVersion = '' then
    Result := '3.2.2'
  else
    Result := FHostFpcVersion;
end;

function TInstallThread.HostFpcBinDir: string;
begin
{$ifdef WINDOWS}
  Result := IncludeTrailingPathDelimiter(
    IncludeTrailingPathDelimiter(FCfg.TargetDir) + HostFpcBinSubdir);
{$endif}
{$ifdef LINUX}
  // Layout is <install>/fpc/lib/fpc/<detected-version>/. Version is
  // probed at runtime by HostFpcVersion -- can't hardcode because the
  // freshly-built unleashed compiler reports its own version (3.3.1+),
  // not the bootstrap's (3.2.2).
  Result := IncludeTrailingPathDelimiter(
    IncludeTrailingPathDelimiter(FCfg.TargetDir) + 'fpc/lib/fpc/' + HostFpcVersion);
{$endif}
end;

function TInstallThread.HostFpcUtilDir: string;
begin
  Result := IncludeTrailingPathDelimiter(
    IncludeTrailingPathDelimiter(FCfg.TargetDir) + HostFpcUtilSubdir);
end;

// Where the cross RTL units land per target:
//   Windows: <install>/fpc/units/<target>/  (sibling of fpc/bin/, NOT under it)
//   Linux:   <install>/fpc/lib/fpc/<ver>/units/<target>/  (under lib, version-keyed)
// Used by the dispatcher's hasCross<arch> detection and by the manifest
// writer to decide what cross targets are physically installed.
function TInstallThread.HostFpcUnitsDir: string;
begin
{$ifdef WINDOWS}
  Result := IncludeTrailingPathDelimiter(
    IncludeTrailingPathDelimiter(FCfg.TargetDir) + 'fpc') + 'units' + PathDelim;
{$endif}
{$ifdef LINUX}
  Result := HostFpcBinDir + 'units' + DirectorySeparator;
{$endif}
end;

// Shell wrapper installed AS bin/fpc that sets PPC_CONFIG_PATH then
// exec's the original launcher (moved to bin/fpc.real). FPC reads
// ~/.fpc.cfg first if present, so without this a stale user cfg
// shadows our portable one for Lazarus and shell invocations.
// Idempotent (shebang check). No-op on Windows.
procedure TInstallThread.InstallFpcWrapper;
begin
{$ifdef LINUX}
  var FpcBin     := HostFpcUtilDir + 'fpc';
  var FpcRealBin := HostFpcUtilDir + 'fpc.real';
  if not FileExists(FpcBin) then Exit;
  // already wrapped? detect by reading the first line for the shebang.
  try
    var probe := autofree TStringList.Create;
    probe.LoadFromFile(FpcBin);
    if (probe.Count > 0) and (Pos('#!/bin/sh', probe[0]) = 1) then begin
      Log('  fpc wrapper already in place, skipping');
      Exit;
    end;
  except
    // unreadable file -- treat as binary and proceed with wrap
  end;
  // back up the real launcher
  if FileExists(FpcRealBin) then SysUtils.DeleteFile(FpcRealBin);
  if not RenameFile(FpcBin, FpcRealBin) then begin
    Log('  WARN: could not rename fpc -> fpc.real (skipping wrapper)');
    Exit;
  end;
  // write wrapper. SCRIPT_DIR via $(dirname $(readlink -f $0)) so the
  // wrapper still finds fpc.real if the install dir gets moved.
  var Wrapper :=
    '#!/bin/sh'#10 +
    '# unleashed-pascal launcher wrapper.'#10 +
    '# Forces PPC_CONFIG_PATH so the portable fpc.cfg next to ppcx64'#10 +
    '# wins over any stale ~/.fpc.cfg from prior FPC experiments.'#10 +
    'SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd -P)"'#10 +
    'export PPC_CONFIG_PATH="$SCRIPT_DIR/../lib/fpc/' + HostFpcVersion + '"'#10 +
    'exec "$SCRIPT_DIR/fpc.real" "$@"'#10;
  var Sl := autofree TStringList.Create;
  Sl.Text := Wrapper;
  try
    Sl.SaveToFile(FpcBin);
  except
    Log('  WARN: could not write fpc wrapper at ' + FpcBin);
    // try to restore the original
    RenameFile(FpcRealBin, FpcBin);
    Exit;
  end;
  RunSilent('/bin/chmod', ['+x', FpcBin]);
  Log('  fpc wrapper installed: ' + FpcBin);
{$endif}
end;

// After `make install` on Linux, ppcx64 / ppcross* end up in
// lib/fpc/<ver>/ but no symlinks land in bin/. The `fpc` launcher
// looks for `ppc<target>` in its own bin/ first; without the symlink
// fpc exits with "ppcx64 can't be executed, code 127" (POSIX ENOENT
// from exec). Distro packaging normally drops these symlinks but the
// upstream Makefile doesn't, so we create them ourselves.
//
// Relative target so the install dir stays movable. No-op on Windows
// (everything sits flat in bin\x86_64-win64\ already).
procedure TInstallThread.EnsureCompilerSymlinks;
begin
{$ifdef LINUX}
  var Ver := HostFpcVersion;
  if Ver = '3.2.2' then Exit;   // pre-install fallback, nothing to link
  // Walk lib/fpc/<ver>/ and symlink every ppc* binary into bin/.
  var SR: TSearchRec;
  if FindFirst(HostFpcBinDir + 'ppc*', faAnyFile, SR) = 0 then
  try
    repeat
      if (SR.Name <> '.') and (SR.Name <> '..') and ((SR.Attr and faDirectory) = 0) then
        RunSilent('/bin/ln', ['-sf', '../lib/fpc/' + Ver + '/' + SR.Name, HostFpcUtilDir + SR.Name]);
    until FindNext(SR) <> 0;
  finally
    FindClose(SR);
  end;
{$endif}
end;

// recursive directory removal -- ignores missing target. On Windows
// shells `cmd /C rmdir /S /Q`; on Linux invokes `/bin/rm -rf`. Used
// throughout the pipeline for cleanup of fpcsrc/, lazarus/, cross/...
procedure TInstallThread.RemoveDir(const Path: string);
begin
{$ifdef WINDOWS}
  RunSilent('cmd.exe', ['/C', 'rmdir', '/S', '/Q', Path]);
{$endif}
{$ifdef LINUX}
  RunSilent('/bin/rm', ['-rf', Path]);
{$endif}
end;

// verbose removal for the multi-minute cleans: logs the delete command per subdir (two levels
// down) and sweeps the current stage's progress across [pctFrom..pctTo]; a silent RemoveDir on
// a tree like fpcsrc (~60k files) otherwise looks like a hang for several minutes
procedure TInstallThread.removeDirVerbose(const path: string; pctFrom, pctTo: Integer);
{$ifdef WINDOWS}
const RM_CMD = 'rmdir /S /Q ';
{$endif}
{$ifdef LINUX}
const RM_CMD = 'rm -rf ';
{$endif}

  procedure listEntries(const dir: string; dirs, files: TStringList);
  var sr: TSearchRec;
  begin
    if FindFirst(IncludeTrailingPathDelimiter(dir)+'*', faAnyFile, sr) = 0 then
    try
      repeat
        if (sr.Name = '.') or (sr.Name = '..') then Continue;
        if (sr.Attr and faDirectory) <> 0 then dirs.Add(sr.Name) else files.Add(sr.Name);
      until FindNext(sr) <> 0;
    finally
      SysUtils.FindClose(sr);
    end;
  end;

begin
  if not DirectoryExists(path) then exit;
  Log('Removing '+path);
  var topDirs  := autofree TStringList.Create;
  var topFiles := autofree TStringList.Create;
  listEntries(path, topDirs, topFiles);
  for var i := 0 to topDirs.Count-1 do begin
    var sub       := IncludeTrailingPathDelimiter(path)+topDirs[i];
    var sliceFrom := pctFrom+((pctTo-pctFrom)*i) div (topDirs.Count+1);
    var sliceTo   := pctFrom+((pctTo-pctFrom)*(i+1)) div (topDirs.Count+1);
    Progress(sliceFrom, 'removing '+topDirs[i]);
    // one level deeper so the biggest trees (fpcsrc\packages holds most of the files) show flow
    var subDirs  := autofree TStringList.Create;
    var subFiles := autofree TStringList.Create;
    listEntries(sub, subDirs, subFiles);
    for var j := 0 to subDirs.Count-1 do begin
      Log('  '+RM_CMD+IncludeTrailingPathDelimiter(sub)+subDirs[j]);
      Progress(sliceFrom+((sliceTo-sliceFrom)*j) div subDirs.Count, 'removing '+topDirs[i]+DirectorySeparator+subDirs[j]);
      RemoveDir(IncludeTrailingPathDelimiter(sub)+subDirs[j]);
    end;
    // leftover files + the (now shallow) dir itself
    Log('  '+RM_CMD+sub);
    RemoveDir(sub);
  end;
  for var i := 0 to topFiles.Count-1 do SysUtils.DeleteFile(IncludeTrailingPathDelimiter(path)+topFiles[i]);
  RemoveDir(path);
  Progress(pctTo, 'removed '+path);
end;

function TInstallThread.StepBootstrap: Boolean;
begin
  Result := False;
  var ZipFile      := IncludeTrailingPathDelimiter(GetTempDir) + BOOTSTRAP_ZIP_NAME;
  var BootstrapDir := IncludeTrailingPathDelimiter(FCfg.TargetDir) + 'fpc322';

  Log('Downloading portable bootstrap FPC 3.2.2');
  Log('  URL: ' + BOOTSTRAP_URL);
  Progress(0, 'Downloading bootstrap...');
  if not DownloadFile(BOOTSTRAP_URL, ZipFile, @Progress) then begin
    FErrorMsg := 'bootstrap download failed';
    Exit;
  end;

  Log('Verifying SHA256...');
  Progress(-1, 'Verifying SHA256');
  var ActualHash := SHA256OfFile(ZipFile);
  if ActualHash <> BOOTSTRAP_SHA then begin
    Log('  expected: ' + BOOTSTRAP_SHA);
    Log('  actual:   ' + ActualHash);
    FErrorMsg := 'bootstrap SHA256 mismatch';
    Exit;
  end;
  Log('  OK');

  Log('Extracting bootstrap to ' + BootstrapDir);
  Progress(0, 'Extracting bootstrap...');
  if not ExtractZip(ZipFile, BootstrapDir, @Progress) then begin
    FErrorMsg := 'bootstrap extract failed';
    Exit;
  end;
  DeleteFile(ZipFile);

{$ifdef LINUX}
  // ZIP does not preserve unix exec bits (TUnZipper drops them); restore
  // +x on every file under bin/ (fpc wrapper, fpcmkcfg, fpcres, ...) and
  // on the compiler binary in lib/fpc/3.2.2/. -R + glob covers all the
  // bin/ utilities in one shot.
  RunSilent('/bin/chmod', ['-R', '+x', IncludeTrailingPathDelimiter(BootstrapDir) + 'bin']);
  RunSilent('/bin/chmod', ['+x', IncludeTrailingPathDelimiter(BootstrapDir) + 'lib/fpc/3.2.2/ppcx64']);
{$endif}

  Log('Bootstrap ready: ' + IncludeTrailingPathDelimiter(BootstrapBinDir) +
      BootstrapPpName + ExeExt);
  Result := True;
end;

// after extract, codeload leaves a single top-level dir like
// "compiler-abc123def..." containing the actual source. find that one
// directory in ParentDir; return '' if not exactly one dir there.
function FindOnlyTopDir(const ParentDir: string): string;
var
  SR: TSearchRec;
  Count: Integer;
begin
  Result := '';
  Count := 0;
  if FindFirst(IncludeTrailingPathDelimiter(ParentDir) + '*', faDirectory, SR) = 0 then begin
    repeat
      if (SR.Name = '.') or (SR.Name = '..') then Continue;
      if (SR.Attr and faDirectory) = 0 then Continue;
      Inc(Count);
      if Count = 1 then Result := SR.Name
      else Result := '';  // more than one - bail
    until FindNext(SR) <> 0;
    FindClose(SR);
  end;
  if Count <> 1 then Result := '';
end;

function TInstallThread.StepDownloadFpcSource: Boolean;
begin
  Result := False;
  var Ref     := ResolveFpcRef;
  var Url     := FPC_SOURCE_URL_PREFIX + Ref;
  var ZipFile := IncludeTrailingPathDelimiter(GetTempDir) + 'unleashed-pascal-source.zip';
  var Target  := MakeWorkDir;
  // hidden temp parent so FindOnlyTopDir works regardless of siblings
  // (fpc, fpc322, lazarus, ...) already living in TargetDir
  var TempParent := IncludeTrailingPathDelimiter(FCfg.TargetDir) + '.fpcsrc-extract';

  if DirectoryExists(Target) then removeDirVerbose(Target, 0, 10);
  if DirectoryExists(TempParent) then
    RemoveDir(TempParent);
  ForceDirectories(TempParent);

  Log('Downloading unleashed-pascal source (ref=' + Ref + ')');
  Log('  URL: ' + Url);
  Progress(0, 'Downloading source...');
  if not DownloadFile(Url, ZipFile, @Progress) then begin
    FErrorMsg := 'source download failed';
    Exit;
  end;

  Log('Extracting source');
  Progress(0, 'Extracting source...');
  if not ExtractZip(ZipFile, TempParent, @Progress) then begin
    FErrorMsg := 'source extract failed';
    Exit;
  end;
  DeleteFile(ZipFile);

  // codeload top dir is "compiler-<sha>"; rename it to "fpcsrc"
  var ExtractedTopDir := FindOnlyTopDir(TempParent);
  if ExtractedTopDir = '' then begin
    FErrorMsg := 'unexpected source archive layout (no single top dir)';
    Exit;
  end;
  if not RenameFile(IncludeTrailingPathDelimiter(TempParent) + ExtractedTopDir, Target) then begin
    FErrorMsg := 'cannot rename ' + ExtractedTopDir + ' to fpcsrc';
    Exit;
  end;
  RemoveDir(TempParent);

  Log('Source ready: ' + Target);
  Result := True;
end;

// one-shot dump of the inherited env vars that point FPC at another
// install. proc_util strips them from every child, so this is purely a
// breadcrumb for bug reports: a build that pulls units out of a foreign
// directory is otherwise impossible to explain from the make output.
procedure TInstallThread.logHostFpcEnv;
const
  FPC_SEARCH_VARS: array[0..4] of string = ('FPCDIR', 'PPC_CONFIG_PATH', 'WIN32UNITS', 'WIN64UNITS', 'LINUXUNITS');
begin
  for var name in FPC_SEARCH_VARS do begin
    var value := GetEnvironmentVariable(name);
    if value <> '' then Log('  NOTE: host env has '+name+'='+value+' (dropped for child builds)');
  end;
end;

// `-n @<cfg>` for every fpc a makefile spawns. One flag does what the env pin
// needs three vars for: it drops the config search AND the built-in FPCDIR /
// <TARGET>UNITS unit paths. Empty when the path holds a space - make splits OPT
// on whitespace, and quoting through make into fpc is not portable; the
// PPC_CONFIG_PATH pin covers that case on its own.
function TInstallThread.makeCfgOpt: string;
begin
  result := '';
  var cfg := HostFpcBinDir + 'fpc.cfg';
  if not FileExists(cfg) then Exit;
  if Pos(' ', cfg) > 0 then begin
    // 8.3 aliasing is off on most volumes these days, so this often fails
    var shortCfg := ExtractShortPathName(cfg);
    if (shortCfg = '') or (Pos(' ', shortCfg) > 0) then Exit;
    cfg := shortCfg;
  end;
  result := '-n @'+cfg;
end;

// run make with the given args from the source dir. On Windows the
// bootstrap zip ships its own make.exe + binutils (as.exe, ld.exe,
// ar.exe), so we point make at the bootstrap copy and prepend the
// bootstrap bin dir to PATH. On Linux we use the system `make`
// (build-essential) from PATH and rely on system binutils (also in
// PATH already); the FPC linux bootstrap zip does not bundle GNU make.
function TInstallThread.RunMake(const Args: array of string;
  const StepLabel: string): Boolean;
begin
{$ifdef WINDOWS}
  var MakeExe    := IncludeTrailingPathDelimiter(BootstrapBinDir) + 'make.exe';
  var PathPrefix := BootstrapBinDir;
{$endif}
{$ifdef LINUX}
  var MakeExe    := 'make';      // TProcess finds it via PATH
  // FPC Makefile (~lines 105-140) runs `$(FPC) -iVSPTPSOTO` to detect
  // the compiler. If $(FPC) resolves empty, FULL_TARGET becomes '-'
  // and Makefile:252 errors "doesn't support target -". Prepend both
  // bootstrap bin/ (launcher) and lib/fpc/3.2.2/ (actual ppcx64) to
  // PATH so the detection succeeds. On Windows the i386-win32
  // bootstrap ships fpc.exe and make.exe in the same dir, already
  // covered by BootstrapBinDir.
  var BootstrapBinUnix := IncludeTrailingPathDelimiter(
    IncludeTrailingPathDelimiter(FCfg.TargetDir) + 'fpc322') + 'bin';
  var PathPrefix := BootstrapBinUnix + PathSeparator + BootstrapBinDir;
  // diagnostic: one-shot dump of which make we'll exec + what's in
  // parent env that could affect it. helps trace cases where the
  // distro ships a make wrapper (ccache, etc.) or leaves MAKEFLAGS
  // hanging in the user's shell.
  if not FLoggedMakeDiag then begin
    FLoggedMakeDiag := True;
    Log('  diag: parent MAKEFLAGS=' + GetEnvironmentVariable('MAKEFLAGS'));
    Log('  diag: parent MFLAGS='    + GetEnvironmentVariable('MFLAGS'));
    Log('  diag: parent PATH='      + Copy(GetEnvironmentVariable('PATH'), 1, 200) + '...');
    // try to resolve which `make` will be picked from PATH
    var WhichOut := autofree TStringList.Create;
    var TmpFile  := GetTempFileName(GetTempDir(False), 'unl-which');
    if RunSilent('/bin/sh', ['-c', 'which make > ' + TmpFile + ' 2>&1; readlink -f $(which make) >> ' + TmpFile]) = 0 then
    try
      WhichOut.LoadFromFile(TmpFile);
      Log('  diag: resolved make: ' + Trim(WhichOut.Text));
    except
    end;
    if FileExists(TmpFile) then SysUtils.DeleteFile(TmpFile);
  end;
{$endif}
  var ArgList := '';
  for var i := Low(Args) to High(Args) do begin
    if ArgList <> '' then ArgList := ArgList + ' ';
    ArgList := ArgList + Args[i];
  end;
  Log('Running: make ' + ArgList);
  Progress(-1, StepLabel);
  var ExitCode := RunStream(MakeExe, Args, MakeWorkDir, PathPrefix, @OnMakeLine);
  Result := ExitCode = 0;
  if not Result then begin
    FErrorMsg := StepLabel + ' failed (make exit=' + IntToStr(ExitCode) + ')';
    Log('  ' + FErrorMsg);
  end;
end;

function TInstallThread.StepBuildFpcNative: Boolean;
begin
  Result := False;
  // On Windows the bootstrap PP is ppc386.exe (FPC 3.2.2 i386 native);
  // it cross-builds the host x86_64 compiler. The diagnostic scripts
  // proved this path end-to-end; switching to a x86_64-targeting
  // bootstrap broke `make all` for the native step (system.inc could
  // not find x86_64.inc). On Linux the bootstrap is the upstream
  // x86_64-linux portable tarball; PP is the native ppcx64.
  var PpBootstrap      := IncludeTrailingPathDelimiter(BootstrapBinDir) + BootstrapPpName + ExeExt;
  var WorkDir          := MakeWorkDir;
  // PpSelf: the freshly-built host compiler that lives in fpcsrc/compiler/
  // after `make all` -- used as PP for the subsequent `utils` + `install`
  // targets (the bootstrap PP would re-emit i386 / older code).
  var PpSelf           := IncludeTrailingPathDelimiter(WorkDir) +
                          'compiler' + DirectorySeparator + 'ppcx64' + ExeExt;
  var FpcInstallPrefix := IncludeTrailingPathDelimiter(FCfg.TargetDir) + 'fpc';

  // Win64 lacks native 80-bit Extended so the native ppcx64.exe must
  // be built with the same `-dFPC_SOFT_FPUX80` as the cross compilers.
  // OS-only cross (same CPU, different OS) keeps ppcx64.exe per
  // compiler/utils/fpc.pp:480-484, so a soft-x80 cross-rtl loaded by
  // a native compiler without the flag IEs 200208151 on first .ppu
  // read. Linux x86_64 has native x87 Extended and needs no flag.
{$ifdef WINDOWS}
  var SoftX80: TStringArray := ['OPT=-dFPC_SOFT_FPUX80'];
{$endif}
{$ifdef LINUX}
  var SoftX80: TStringArray := [];
{$endif}

  Log('--- Building native FPC x86_64-' + HostTargetOs + ' ---');
  Log('  source dir:      ' + WorkDir);
  Log('  bootstrap PP:    ' + PpBootstrap);
  Log('  install prefix:  ' + FpcInstallPrefix);
{$ifdef WINDOWS}
  Log('  soft-x80:        enabled (Win64 host lacks native Extended)');
{$endif}

  // distclean is brief; bundle it under "make all" stage start
  SetStage(isFpcMakeAll);
  if not RunMake(['distclean'], 'make distclean') then Exit;

  if not RunMake(
    ['all', 'OS_TARGET=' + HostTargetOs, 'CPU_TARGET=x86_64', 'PP=' + PpBootstrap] + SoftX80, 'make all (native FPC, ~5-10 min)') then Exit;

  SetStage(isFpcMakeUtils);
  if not RunMake(
    ['utils', 'OS_TARGET=' + HostTargetOs, 'CPU_TARGET=x86_64', 'PP=' + PpSelf] + SoftX80, 'make utils') then Exit;

  SetStage(isFpcMakeInstall);
  if not RunMake(
    ['install', 'OS_TARGET=' + HostTargetOs, 'CPU_TARGET=x86_64', 'INSTALL_PREFIX=' + FpcInstallPrefix, 'PP=' + PpSelf] + SoftX80, 'make install') then Exit;

  // On Linux, `make install` doesn't drop bin/ppc* symlinks; the
  // distro packaging usually does. Without them `fpc` launcher exits
  // with code 127 because it can't find ppc<target> in its own dir.
  // No-op on Windows (flat bin\<target>\ layout already has ppcXXX).
  EnsureCompilerSymlinks;
  // Wrap bin/fpc so that ANY invocation (shell, Lazarus IDE,
  // makefiles) gets PPC_CONFIG_PATH set automatically. Defends
  // against stale ~/.fpc.cfg without needing user action. No-op on
  // Windows, where fpc.exe is the real driver binary; our own child
  // processes get PPC_CONFIG_PATH from proc_util instead.
  InstallFpcWrapper;

  Log('--- Native FPC ready: ' + HostFpcBinDir + 'ppcx64' + ExeExt + ' ---');
  Result := True;
end;

function TInstallThread.StepBuildFpcCross: Boolean;
begin
  Result := False;
  var PpSelf           := HostFpcBinDir + 'ppcx64' + ExeExt;
  var FpcInstallPrefix := IncludeTrailingPathDelimiter(FCfg.TargetDir) + 'fpc';

  Log('--- Building cross-compiler i386-win32 ---');
  // -dFPC_SOFT_FPUX80 is mandatory here because the target is i386 and
  // the host (x86_64-win64) does not define FPC_HAS_TYPE_EXTENDED. The
  // hard gate at fpcdefs.inc:432 ('Cross-compiling from systems without
  // support for an 80 bit extended floating point type to i386 is not
  // yet supported') fires otherwise.
  if not RunMake(
    ['crossinstall', 'OS_TARGET=win32', 'CPU_TARGET=i386', 'INSTALL_PREFIX=' + FpcInstallPrefix, 'PP=' + PpSelf, 'OPT=-dFPC_SOFT_FPUX80'], 'make crossinstall (i386-win32, ~5 min)') then Exit;

  Log('--- Cross-compiler ready: ' + HostFpcBinDir + 'ppcross386' + ExeExt + ' ---');
  Result := True;
end;

function copyFileTo(const src, dst: string): Boolean;
begin
  result := False;
  try
    var s := autofree TFileStream.Create(src, fmOpenRead or fmShareDenyWrite);
    var d := autofree TFileStream.Create(dst, fmCreate);
    d.CopyFrom(s, 0);
    result := True;
  except
    on E: Exception do result := False;
  end;
end;

{$ifdef WINDOWS}
// native win64 external assembling (-a, -al, -as, -Xe) expects as.exe/ld.exe
// beside the compiler; we build from source so nothing ever put them there.
// Fetch FPC's own statically-linked set into fpc\bin\x86_64-win64\.
function TInstallThread.stepStageWin64Binutils: Boolean;
begin
  result := True;
  if FileExists(HostFpcBinDir+'as.exe') then exit;
  result := False;

  Log('Staging x86_64-win64 binutils in '+HostFpcBinDir);
  var zip := IncludeTrailingPathDelimiter(GetTempDir)+'binutils-win64.zip';
  if not DownloadAndVerify(BINW64_URL, BINW64_SHA, zip, 'binutils x86_64-win64') then exit;
  if not ExtractZip(zip, ExcludeTrailingPathDelimiter(HostFpcBinDir), @Progress) then begin
    FErrorMsg := 'binutils x86_64-win64 extract failed';
    exit;
  end;
  DeleteFile(zip);
  result := True;
end;
{$endif}

// win32 needs real binutils as soon as anything forces external assembling
// (-a, -al, -as, -Xe); the default internal writer path never touches them.
// fpcmkcfg's stock cfg defines NEEDCROSSBINUTILS for every non-win64 target
// and emits -XP$FPCTARGET-, so without these the compiler stops with
// "Assembler i386-win32-as.exe not found". The 3.2.2 bootstrap ships a
// matching i386 set (binutils 2.28, pe-i386), so no extra download.
function TInstallThread.stepStageWin32Binutils(add: Boolean): Boolean;
var
  tools: TStringArray;
begin
  result := False;
  tools := ['as', 'ld', 'ar', 'nm', 'objcopy', 'objdump', 'strip', 'windres', 'dlltool'];
  var binDir := IncludeTrailingPathDelimiter(FCfg.TargetDir)+'cross'+DirectorySeparator+'i386-win32'+DirectorySeparator+'bin';
  var srcDir := IncludeTrailingPathDelimiter(BootstrapBinDir);

  if not add then begin
    for var i := 0 to High(tools) do DeleteFile(IncludeTrailingPathDelimiter(binDir)+'i386-win32-'+tools[i]+ExeExt);
    RemoveDir(binDir);
    exit(PatchFpcCfgCrossSection('win32', 'i386', '', '', '', False));
  end;

  if not ForceDirectories(binDir) then begin
    FErrorMsg := 'cannot create '+binDir;
    exit;
  end;

  Log('Staging i386-win32 binutils in '+binDir);
  for var i := 0 to High(tools) do begin
    var src := srcDir+tools[i]+ExeExt;
    var dst := IncludeTrailingPathDelimiter(binDir)+'i386-win32-'+tools[i]+ExeExt;
    if FileExists(dst) then Continue;
    if not FileExists(src) then begin
      Log('  missing '+src+', skipped');
      Continue;
    end;
    if not copyFileTo(src, dst) then begin
      FErrorMsg := 'cannot copy '+src+' -> '+dst;
      Log('  '+FErrorMsg);
      exit;
    end;
  end;

  result := PatchFpcCfgCrossSection('win32', 'i386', binDir, '', 'i386-win32-', True);
end;

function TInstallThread.StepBuildFpcCrossWasm: Boolean;
begin
  Result := False;
  var PpSelf           := HostFpcBinDir + 'ppcx64' + ExeExt;
  var FpcInstallPrefix := IncludeTrailingPathDelimiter(FCfg.TargetDir) + 'fpc';

  Log('--- Building cross-compiler wasm32-wasip1 ---');
  // FPC has an internal WASM linker; no external binutils or libc to
  // bundle. wasm bytecode is its own format (not ELF), so the
  // crossinstall produces only ppcrosswasm32 + RTL units.
  // OS target is "wasip1" (WASI Preview 1); the older "wasi" alias is
  // not understood by the current Makefile.
  if not RunMake(
    ['crossinstall', 'OS_TARGET=wasip1', 'CPU_TARGET=wasm32', 'INSTALL_PREFIX=' + FpcInstallPrefix, 'PP=' + PpSelf], 'make crossinstall (wasm32-wasip1, ~2 min)') then Exit;

  Log('--- Cross-compiler ready: ' + HostFpcBinDir + 'ppcrosswasm32' + ExeExt + ' ---');
  // stock cfg defines NEEDCROSSBINUTILS for any target that is not i386 /
  // amd64, so wasm32 inherits -XPwasm32-wasip1- and external assembling
  // (-al -Awasa) hunts for wasm32-wasip1-wasa.exe. FPC's own wasa lives
  // unprefixed next to the compiler; reset the prefix to that directory.
  result := PatchFpcCfgCrossSection('wasip1', 'wasm32', ExcludeTrailingPathDelimiter(HostFpcBinDir), '', '', True);
end;

function TInstallThread.StepRemoveCrossWasm: Boolean;
begin
  Result := True;  // best-effort
  var FpcInstall := IncludeTrailingPathDelimiter(FCfg.TargetDir) + 'fpc';
  var PpcrossBin := HostFpcBinDir + 'ppcrosswasm32' + ExeExt;
  var UnitsDir   := IncludeTrailingPathDelimiter(FpcInstall) +
                    'units' + DirectorySeparator + 'wasm32-wasip1';

  Log('Removing cross compiler wasm32-wasip1');
  Progress(-1, 'Removing wasm32-wasip1');
  if FileExists(PpcrossBin) then begin
    Log('  ' + PpcrossBin);
    DeleteFile(PpcrossBin);
  end;
  if DirectoryExists(UnitsDir) then begin
    Log('  ' + UnitsDir);
    RemoveDir(UnitsDir);
  end;
  PatchFpcCfgCrossSection('wasip1', 'wasm32', '', '', '', False);
end;

// download a zip to DestZip and verify its SHA256 matches the pinned Sha.
// Body of the network IO + hash check shared between cross-Linux 64/32
// (each pulls two zips: BIN binutils + LIB glibc/runtime).
function TInstallThread.DownloadAndVerify(const Url, Sha, DestZip, StepLabel: string): Boolean;
begin
  Result := False;
  Log('Downloading ' + StepLabel);
  Log('  URL: ' + Url);
  Progress(0, 'Downloading ' + StepLabel + '...');
  if not DownloadFile(Url, DestZip, @Progress) then begin
    FErrorMsg := StepLabel + ' download failed';
    Exit;
  end;
  Progress(-1, 'Verifying SHA256');
  var ActualHash := SHA256OfFile(DestZip);
  if not SameText(ActualHash, Sha) then begin
    Log('  expected: ' + Sha);
    Log('  actual:   ' + ActualHash);
    FErrorMsg := StepLabel + ' SHA256 mismatch';
    Exit;
  end;
  Log('  OK');
  Result := True;
end;

// add or remove a per-target cross-compile section in fpc.cfg. Each
// section is wrapped in tagged BEGIN/END comments so re-installs can
// strip the previous version cleanly without accumulating duplicates.
// Add=False simply removes any existing tagged block (used by
// StepRemoveCrossLinux*).
function TInstallThread.PatchFpcCfgCrossSection(const TargetOs, TargetCpu, BinDir, LibDir, BinPrefix: string; Add: Boolean): Boolean;
begin
  Result := False;
  var CfgPath := HostFpcBinDir + 'fpc.cfg';
  if not FileExists(CfgPath) then begin
    Log('  fpc.cfg not present yet; skipping cross-section patch');
    Result := True;
    Exit;
  end;

  var Tag := '# unleashed-pascal-cross ' + TargetCpu + '-' + TargetOs;
  // tag written by pre-rename installer versions; still stripped so
  // updating an old install does not accumulate duplicate sections
  var OldTag := '# fpc-unleashed-cross ' + TargetCpu + '-' + TargetOs;
  var Lines := autofree TStringList.Create;
  try
    Lines.LoadFromFile(CfgPath);
  except
    on E: Exception do begin
      FErrorMsg := 'cannot read fpc.cfg: ' + E.Message;
      Exit;
    end;
  end;

  // strip any existing block with this tag (current or pre-rename)
  for var CurTag in [Tag, OldTag] do begin
    var i := 0;
    while i < Lines.Count do begin
      if Pos('# BEGIN ' + CurTag, Lines[i]) > 0 then begin
        var endIdx := i;
        while (endIdx < Lines.Count) and (Pos('# END ' + CurTag, Lines[endIdx]) = 0) do
          Inc(endIdx);
        if endIdx < Lines.Count then begin
          for var k := endIdx downto i do
            Lines.Delete(k);
          Continue;
        end;
      end;
      Inc(i);
    end;
  end;

  if Add then begin
    Lines.Add('# BEGIN ' + Tag);
    Lines.Add('#ifdef ' + TargetOs);
    Lines.Add('#ifdef cpu' + TargetCpu);
    Lines.Add('-XP' + IncludeTrailingPathDelimiter(BinDir) + BinPrefix);
    Lines.Add('-FD' + BinDir);
    if LibDir <> '' then Lines.Add('-Fl'+LibDir);
    Lines.Add('#endif');
    Lines.Add('#endif');
    Lines.Add('# END ' + Tag);
  end;

  try
    Lines.SaveToFile(CfgPath);
    Result := True;
  except
    on E: Exception do begin
      FErrorMsg := 'cannot write fpc.cfg: ' + E.Message;
      Log('  ' + FErrorMsg);
    end;
  end;
end;

// Common make args shared by every Linux cross stage. Spelling out
// CPU_SOURCE/OS_SOURCE/FPCDIR/FPCFPMAKE keeps make from inferring the
// host triple from PP -- without them, an i386 PP makes make think the
// source platform is i386, which breaks the host fpmkunit bootstrap
// during packages_all.
function TInstallThread.LinuxCommonMakeArgs(const TargetCpu, BinDir, LibDir, BinPrefix: string): TStringArray;
begin
  Result := [
    'OS_TARGET=linux', 'CPU_TARGET=' + TargetCpu, 'OS_SOURCE=' + HostTargetOs, 'CPU_SOURCE=x86_64',
    'FPCDIR=' + MakeWorkDir, 'FPCFPMAKE=' + HostFpcBinDir + 'ppcx64' + ExeExt, 'INSTALL_PREFIX=' + IncludeTrailingPathDelimiter(FCfg.TargetDir) + 'fpc', 'BINUTILSPREFIX=' + BinPrefix,
    'CROSSBINDIR=' + BinDir, 'CROSSOPT=-Fl' + LibDir, 'CROSSINSTALL=1'
  ];
end;

// Shared download+extract for both Linux cross zips. Returns False on
// any failure with FErrorMsg set; the caller logs context.
function TInstallThread.UnpackLinuxCross(const Tag, BinUrl, BinSha, LibUrl, LibSha, BinDir, LibDir: string): Boolean;
begin
  Result := False;
  ForceDirectories(BinDir);
  ForceDirectories(LibDir);

  var BinZip := IncludeTrailingPathDelimiter(GetTempDir) + 'cross-' + Tag + '-bin.zip';
  if not DownloadAndVerify(BinUrl, BinSha, BinZip, 'cross-binutils ' + Tag) then Exit;
  Progress(0, 'Extracting binutils...');
  if not ExtractZip(BinZip, BinDir, @Progress) then begin
    FErrorMsg := 'cross-binutils ' + Tag + ' extract failed';
    Exit;
  end;
  DeleteFile(BinZip);

  var LibZip := IncludeTrailingPathDelimiter(GetTempDir) + 'cross-' + Tag + '-lib.zip';
  if not DownloadAndVerify(LibUrl, LibSha, LibZip, 'cross-libs ' + Tag) then Exit;
  Progress(0, 'Extracting libs...');
  if not ExtractZip(LibZip, LibDir, @Progress) then begin
    FErrorMsg := 'cross-libs ' + Tag + ' extract failed';
    Exit;
  end;
  DeleteFile(LibZip);

  Result := True;
end;

function TInstallThread.StepBuildFpcCrossLinux64: Boolean;
begin
  Result := False;
  // Staged sequence instead of `make crossinstall`:
  //   compiler_cycle + compiler_install -> FPC=<host ppcx64>, OPT=-dFPC_SOFT_FPUX80
  //   rtl_*, packages_*                 -> FPC=<just-built ppcrossx64>, no OPT
  // A single FPC=<host> across the whole crossinstall trips IE 200208151
  // (with soft-x80) or IE 2015030501 (without).

  var CrossDir := IncludeTrailingPathDelimiter(FCfg.TargetDir) +
                  'cross' + DirectorySeparator + 'x86_64-linux';
  var BinDir   := IncludeTrailingPathDelimiter(CrossDir) + 'bin';
  var LibDir   := IncludeTrailingPathDelimiter(CrossDir) + 'lib';

  Log('--- Building cross-compiler x86_64-linux ---');
  if not UnpackLinuxCross('x86_64-linux', CROSS_LINUX64_BIN_URL, CROSS_LINUX64_BIN_SHA, CROSS_LINUX64_LIB_URL, CROSS_LINUX64_LIB_SHA, BinDir, LibDir) then Exit;

  var PpHost           := HostFpcBinDir + 'ppcx64' + ExeExt;
  var PpCrossInstalled := HostFpcBinDir + 'ppcrossx64' + ExeExt;
  var Common           := LinuxCommonMakeArgs('x86_64', BinDir, LibDir, 'x86_64-linux-gnu-');

  // stage 1: compiler_cycle (host PP + soft-x80) -> produces ppcrossx64
  Log('  stage 1/6: compiler_cycle (build ppcrossx64 with soft-x80)');
  if not RunMake(
    ['compiler_cycle', 'FPC=' + PpHost, 'OPT=-dFPC_SOFT_FPUX80'] + Common, 'compiler_cycle (x86_64-linux, ~3 min)') then Exit;

  var PpCrossBuilt := IncludeTrailingPathDelimiter(MakeWorkDir) +
                      'compiler' + DirectorySeparator + 'ppcrossx64' + ExeExt;
  if not FileExists(PpCrossBuilt) then begin
    FErrorMsg := 'compiler_cycle did not produce ' + PpCrossBuilt;
    Log('  ' + FErrorMsg);
    Exit;
  end;
  Log('  freshly-built ppcrossx64: ' + PpCrossBuilt);

  // stage 2: compiler_install (still host PP) -> copies ppcrossx64 to bin/
  Log('  stage 2/6: compiler_install (place ppcrossx64 in bin/)');
  if not RunMake(
    ['compiler_install', 'FPC=' + PpHost] + Common, 'compiler_install (x86_64-linux)') then Exit;

  var PpForRtl := if FileExists(PpCrossInstalled) then PpCrossInstalled else PpCrossBuilt;
  Log('  using cross compiler for RTL/packages: ' + PpForRtl);

  // stages 3-4: rtl_all + rtl_install, FPC=cross compiler, no OPT
  Log('  stage 3/6: rtl_all (RTL via ppcrossx64)');
  if not RunMake(['rtl_all',     'FPC=' + PpForRtl] + Common, 'rtl_all (x86_64-linux)') then Exit;
  Log('  stage 4/6: rtl_install');
  if not RunMake(['rtl_install', 'FPC=' + PpForRtl] + Common, 'rtl_install (x86_64-linux)') then Exit;

  // stages 5-6: packages
  Log('  stage 5/6: packages_all (packages via ppcrossx64)');
  if not RunMake(['packages_all',     'FPC=' + PpForRtl] + Common, 'packages_all (x86_64-linux, ~3 min)') then Exit;
  Log('  stage 6/6: packages_install');
  if not RunMake(['packages_install', 'FPC=' + PpForRtl] + Common, 'packages_install (x86_64-linux)') then Exit;

  if not PatchFpcCfgCrossSection('linux', 'x86_64', BinDir, LibDir, 'x86_64-linux-gnu-', True) then Exit;

  Log('--- Cross-compile to x86_64-linux ready ---');
  Result := True;
end;

function TInstallThread.StepRemoveCrossLinux64: Boolean;
begin
  Result := True;  // best-effort
  var CrossDir := IncludeTrailingPathDelimiter(FCfg.TargetDir) +
                  'cross' + DirectorySeparator + 'x86_64-linux';
  var UnitsDir := IncludeTrailingPathDelimiter(FCfg.TargetDir) +
                  'fpc' + DirectorySeparator + 'units' +
                  DirectorySeparator + 'x86_64-linux';

  Log('Removing cross compiler x86_64-linux');
  Progress(-1, 'Removing x86_64-linux');
  if DirectoryExists(UnitsDir) then begin
    Log('  ' + UnitsDir);
    RemoveDir(UnitsDir);
  end;
  if DirectoryExists(CrossDir) then begin
    Log('  ' + CrossDir);
    RemoveDir(CrossDir);
  end;
  PatchFpcCfgCrossSection('linux', 'x86_64', '', '', '', False);
end;

function TInstallThread.StepBuildFpcCrossLinux32: Boolean;
begin
  Result := False;
  // i386-linux requires the unleashed ppcross386 (built by the i386-win32
  // cross step). ppcross386 has the i386 codegen and soft-x80 path baked in;
  // it supports both -Twin32 and -Tlinux at runtime, so the same binary
  // serves both targets. Without it, we cannot produce a writer for the
  // cross-RTL whose .ppu the same binary will later read.
  var Pp := HostFpcBinDir + 'ppcross386' + ExeExt;
  if not FileExists(Pp) then begin
    FErrorMsg := 'i386-linux cross requires the i386-win32 cross compiler. ' +
      'Tick "i386-win32" in the cross list as well, then run install.';
    Log('  ' + FErrorMsg);
    Exit;
  end;

  var CrossDir := IncludeTrailingPathDelimiter(FCfg.TargetDir) +
                  'cross' + DirectorySeparator + 'i386-linux';
  var BinDir   := IncludeTrailingPathDelimiter(CrossDir) + 'bin';
  var LibDir   := IncludeTrailingPathDelimiter(CrossDir) + 'lib';

  Log('--- Building cross-compiler i386-linux ---');
  if not UnpackLinuxCross('i386-linux', CROSS_LINUX32_BIN_URL, CROSS_LINUX32_BIN_SHA, CROSS_LINUX32_LIB_URL, CROSS_LINUX32_LIB_SHA, BinDir, LibDir) then Exit;

  var PpHost := HostFpcBinDir + 'ppcx64' + ExeExt;
  var Common := LinuxCommonMakeArgs('i386', BinDir, LibDir, 'i386-linux-gnu-');

  // We deliberately skip compiler_cycle/compiler_install for this target.
  // ppcross386 is already correct; rebuilding via compiler_cycle for
  // OS_TARGET=linux re-stages host RTL with an i386 compiler against
  // win64 source paths and fails on 'Cannot open i386.inc'.
  //
  // A prior `make distclean` (native or earlier cross step) wiped
  // compiler/msgtxt.inc + msgidx.inc; rtl_all needs them via
  // verbose.pas -> cmsgs.pas. Run the `msg` target with the host
  // compiler to regenerate -- cheap, leaves everything else alone.
  Log('  stage 1/5: msg (regenerate compiler/msgtxt.inc + msgidx.inc)');
  if not RunMake(['-C', 'compiler', 'msg', 'FPC=' + PpHost], 'msg (i386-linux prerequisite)') then Exit;

  // stages 2-3: rtl_all + rtl_install, FPC=ppcross386, no OPT
  // (ppcross386 already has soft-x80 baked in from build_win32 step)
  Log('  stage 2/5: rtl_all (RTL via ppcross386)');
  if not RunMake(['rtl_all',     'FPC=' + Pp] + Common, 'rtl_all (i386-linux)') then Exit;
  Log('  stage 3/5: rtl_install');
  if not RunMake(['rtl_install', 'FPC=' + Pp] + Common, 'rtl_install (i386-linux)') then Exit;

  // stages 4-5: packages
  Log('  stage 4/5: packages_all (packages via ppcross386)');
  if not RunMake(['packages_all',     'FPC=' + Pp] + Common, 'packages_all (i386-linux, ~3 min)') then Exit;
  Log('  stage 5/5: packages_install');
  if not RunMake(['packages_install', 'FPC=' + Pp] + Common, 'packages_install (i386-linux)') then Exit;

  if not PatchFpcCfgCrossSection('linux', 'i386', BinDir, LibDir, 'i386-linux-gnu-', True) then Exit;

  Log('--- Cross-compile to i386-linux ready ---');
  Result := True;
end;

function TInstallThread.StepRemoveCrossLinux32: Boolean;
begin
  Result := True;  // best-effort
  var CrossDir := IncludeTrailingPathDelimiter(FCfg.TargetDir) +
                  'cross' + DirectorySeparator + 'i386-linux';
  var UnitsDir := IncludeTrailingPathDelimiter(FCfg.TargetDir) +
                  'fpc' + DirectorySeparator + 'units' +
                  DirectorySeparator + 'i386-linux';

  Log('Removing cross compiler i386-linux');
  Progress(-1, 'Removing i386-linux');
  if DirectoryExists(UnitsDir) then begin
    Log('  ' + UnitsDir);
    RemoveDir(UnitsDir);
  end;
  if DirectoryExists(CrossDir) then begin
    Log('  ' + CrossDir);
    RemoveDir(CrossDir);
  end;
  PatchFpcCfgCrossSection('linux', 'i386', '', '', '', False);
end;

// Cross win64 from linux host using FPC's internal linker (-Xi); no
// mingw-w64 binutils needed. Six-stage build mirrors the linux64-from-
// win64 case (compiler_cycle/install with host PP, rtl_*/packages_*
// with the just-built ppcrossx64) for the same .ppu-compatibility
// reason.
function TInstallThread.StepBuildFpcCrossWin64FromLinux: Boolean;
begin
  Result := False;
  var PpHost           := HostFpcBinDir + 'ppcx64' + ExeExt;
  var PpCrossInstalled := HostFpcBinDir + 'ppcrossx64' + ExeExt;
  var FpcInstallPrefix := IncludeTrailingPathDelimiter(FCfg.TargetDir) + 'fpc';
  // Common args: NO BINUTILSPREFIX / CROSSBINDIR / CROSSOPT -- FPC's
  // internal linker handles PE/COFF without external `as`/`ld`. Pass -Xi
  // via OPT so the compiler is explicit about wanting the internal path
  // even if a system mingw-w64 happens to be in PATH.
  var Common: TStringArray := [
    'OS_TARGET=win64', 'CPU_TARGET=x86_64', 'OS_SOURCE=' + HostTargetOs, 'CPU_SOURCE=x86_64', 'FPCDIR=' + MakeWorkDir, 'FPCFPMAKE=' + PpHost, 'INSTALL_PREFIX=' + FpcInstallPrefix, 'CROSSOPT=-Xi',
    'CROSSINSTALL=1'
  ];

  Log('--- Building cross-compiler x86_64-win64 (internal linker) ---');

  // stage 1: compiler_cycle (host PP) -> produces ppcrossx64 in fpcsrc/compiler/
  Log('  stage 1/6: compiler_cycle (build ppcrossx64 for win64 target)');
  if not RunMake(
    ['compiler_cycle', 'FPC=' + PpHost] + Common, 'compiler_cycle (x86_64-win64, ~3 min)') then Exit;

  var PpCrossBuilt := IncludeTrailingPathDelimiter(MakeWorkDir) +
                      'compiler' + DirectorySeparator + 'ppcrossx64' + ExeExt;
  if not FileExists(PpCrossBuilt) then begin
    FErrorMsg := 'compiler_cycle did not produce ' + PpCrossBuilt;
    Log('  ' + FErrorMsg);
    Exit;
  end;
  Log('  freshly-built ppcrossx64: ' + PpCrossBuilt);

  // stage 2: compiler_install (host PP) -> copy ppcrossx64 to <install>/bin/
  Log('  stage 2/6: compiler_install');
  if not RunMake(
    ['compiler_install', 'FPC=' + PpHost] + Common, 'compiler_install (x86_64-win64)') then Exit;

  var PpForRtl := if FileExists(PpCrossInstalled) then PpCrossInstalled else PpCrossBuilt;
  Log('  using cross compiler for RTL/packages: ' + PpForRtl);

  // stages 3-4: rtl_all + rtl_install -- run with the cross compiler so
  // the .ppu it writes are readable by it later (writer/reader match).
  Log('  stage 3/6: rtl_all (RTL via ppcrossx64)');
  if not RunMake(['rtl_all',     'FPC=' + PpForRtl] + Common, 'rtl_all (x86_64-win64)') then Exit;
  Log('  stage 4/6: rtl_install');
  if not RunMake(['rtl_install', 'FPC=' + PpForRtl] + Common, 'rtl_install (x86_64-win64)') then Exit;

  // stages 5-6: packages (FCL, fpmkunit, winunits-base, ...)
  Log('  stage 5/6: packages_all (packages via ppcrossx64)');
  if not RunMake(['packages_all',     'FPC=' + PpForRtl] + Common, 'packages_all (x86_64-win64, ~3 min)') then Exit;
  Log('  stage 6/6: packages_install');
  if not RunMake(['packages_install', 'FPC=' + PpForRtl] + Common, 'packages_install (x86_64-win64)') then Exit;

  // No fpc.cfg patch needed for win64-from-linux cross: -Xi is enabled
  // by the OPT we pass at build time, and user-side compiles via
  // `fpc -Twin64` rely on the same internal linker. If we later add a
  // mingw-w64 binutils fallback path, it would go here as a cfg block.

  // refresh bin/ symlinks so the newly-built ppcrossx64 is findable
  // through the `fpc` launcher (no-op on Windows).
  EnsureCompilerSymlinks;

  Log('--- Cross-compile to x86_64-win64 ready ---');
  Result := True;
end;

function TInstallThread.StepRemoveCrossWin64FromLinux: Boolean;
begin
  Result := True;  // best-effort
  var PpcrossBin := HostFpcBinDir + 'ppcrossx64' + ExeExt;
  var UnitsDir   := HostFpcUnitsDir + 'x86_64-win64';

  Log('Removing cross compiler x86_64-win64');
  Progress(-1, 'Removing x86_64-win64');
  if FileExists(PpcrossBin) then begin
    Log('  ' + PpcrossBin);
    DeleteFile(PpcrossBin);
  end;
  if DirectoryExists(UnitsDir) then begin
    Log('  ' + UnitsDir);
    RemoveDir(UnitsDir);
  end;
end;

// Build the i386-win32 cross compiler from a x86_64-linux host using the
// FPC internal PE/COFF linker (-Xi). Same staged pattern as the
// x86_64-win64-from-linux step: compiler_cycle to produce ppcross386,
// then rtl + packages with that compiler as FPC=.
//
// No -dFPC_SOFT_FPUX80 here: source host x86_64-linux has native
// extended via System V ABI, target i386 has native x80 in hardware,
// so neither end of the writer/reader pair fakes Extended; the .ppu
// stays consistent.
function TInstallThread.StepBuildFpcCrossWin32FromLinux: Boolean;
begin
  Result := False;
  var PpHost           := HostFpcBinDir + 'ppcx64' + ExeExt;
  var PpCrossInstalled := HostFpcBinDir + 'ppcross386' + ExeExt;
  var FpcInstallPrefix := IncludeTrailingPathDelimiter(FCfg.TargetDir) + 'fpc';
  var Common: TStringArray := [
    'OS_TARGET=win32', 'CPU_TARGET=i386', 'OS_SOURCE=' + HostTargetOs, 'CPU_SOURCE=x86_64', 'FPCDIR=' + MakeWorkDir, 'FPCFPMAKE=' + PpHost, 'INSTALL_PREFIX=' + FpcInstallPrefix, 'CROSSOPT=-Xi',
    'CROSSINSTALL=1'
  ];

  Log('--- Building cross-compiler i386-win32 (internal linker) ---');

  Log('  stage 1/6: compiler_cycle (build ppcross386 for win32 target)');
  if not RunMake(
    ['compiler_cycle', 'FPC=' + PpHost] + Common, 'compiler_cycle (i386-win32, ~3 min)') then Exit;

  var PpCrossBuilt := IncludeTrailingPathDelimiter(MakeWorkDir) +
                      'compiler' + DirectorySeparator + 'ppcross386' + ExeExt;
  if not FileExists(PpCrossBuilt) then begin
    FErrorMsg := 'compiler_cycle did not produce ' + PpCrossBuilt;
    Log('  ' + FErrorMsg);
    Exit;
  end;
  Log('  freshly-built ppcross386: ' + PpCrossBuilt);

  Log('  stage 2/6: compiler_install');
  if not RunMake(
    ['compiler_install', 'FPC=' + PpHost] + Common, 'compiler_install (i386-win32)') then Exit;

  var PpForRtl := if FileExists(PpCrossInstalled) then PpCrossInstalled else PpCrossBuilt;
  Log('  using cross compiler for RTL/packages: ' + PpForRtl);

  Log('  stage 3/6: rtl_all (RTL via ppcross386)');
  if not RunMake(['rtl_all',     'FPC=' + PpForRtl] + Common, 'rtl_all (i386-win32)') then Exit;
  Log('  stage 4/6: rtl_install');
  if not RunMake(['rtl_install', 'FPC=' + PpForRtl] + Common, 'rtl_install (i386-win32)') then Exit;

  Log('  stage 5/6: packages_all (packages via ppcross386)');
  if not RunMake(['packages_all',     'FPC=' + PpForRtl] + Common, 'packages_all (i386-win32, ~3 min)') then Exit;
  Log('  stage 6/6: packages_install');
  if not RunMake(['packages_install', 'FPC=' + PpForRtl] + Common, 'packages_install (i386-win32)') then Exit;

  EnsureCompilerSymlinks;

  Log('--- Cross-compile to i386-win32 ready ---');
  Result := True;
end;

function TInstallThread.StepRemoveCrossWin32FromLinux: Boolean;
begin
  Result := True;  // best-effort
  var PpcrossBin := HostFpcBinDir + 'ppcross386' + ExeExt;
  var UnitsDir   := HostFpcUnitsDir + 'i386-win32';

  Log('Removing cross compiler i386-win32');
  Progress(-1, 'Removing i386-win32');
  if FileExists(PpcrossBin) then begin
    Log('  ' + PpcrossBin);
    DeleteFile(PpcrossBin);
  end;
  if DirectoryExists(UnitsDir) then begin
    Log('  ' + UnitsDir);
    RemoveDir(UnitsDir);
  end;
end;

// Build the i386-linux cross compiler from a x86_64-linux host. Requires
// ppcross386 (produced by StepBuildFpcCrossWin32FromLinux) since the
// same i386 codegen binary serves both -Twin32 and -Tlinux at runtime.
// Skips compiler_cycle: rebuilding ppcross386 for OS_TARGET=linux would
// re-stage host RTL with an i386 compiler against x86_64-linux source
// paths and choke. Just regenerate msg includes (compiler/msgtxt.inc +
// msgidx.inc that distclean wiped) and proceed straight to rtl_all
// using the existing ppcross386 -- same shortcut as the Win-host
// linux32 step (StepBuildFpcCrossLinux32).
function TInstallThread.StepBuildFpcCrossLinux32FromLinux: Boolean;
begin
  Result := False;
  var Pp := HostFpcBinDir + 'ppcross386' + ExeExt;
  if not FileExists(Pp) then begin
    FErrorMsg := 'i386-linux cross requires the i386-win32 cross compiler. ' +
      'Tick "i386-win32" in the cross list as well, then run install again.';
    Log('  ' + FErrorMsg);
    Exit;
  end;

  var PpHost           := HostFpcBinDir + 'ppcx64' + ExeExt;
  var FpcInstallPrefix := IncludeTrailingPathDelimiter(FCfg.TargetDir) + 'fpc';
  var Common: TStringArray := [
    'OS_TARGET=linux', 'CPU_TARGET=i386', 'OS_SOURCE=' + HostTargetOs, 'CPU_SOURCE=x86_64', 'FPCDIR=' + MakeWorkDir, 'FPCFPMAKE=' + PpHost, 'INSTALL_PREFIX=' + FpcInstallPrefix, 'CROSSOPT=-Xi',
    'CROSSINSTALL=1'
  ];

  Log('--- Building cross-compiler i386-linux (internal linker) ---');

  Log('  stage 1/5: msg (regenerate compiler/msgtxt.inc + msgidx.inc)');
  if not RunMake(['-C', 'compiler', 'msg', 'FPC=' + PpHost], 'msg (i386-linux prerequisite)') then Exit;

  Log('  stage 2/5: rtl_all (RTL via ppcross386)');
  if not RunMake(['rtl_all',     'FPC=' + Pp] + Common, 'rtl_all (i386-linux)') then Exit;
  Log('  stage 3/5: rtl_install');
  if not RunMake(['rtl_install', 'FPC=' + Pp] + Common, 'rtl_install (i386-linux)') then Exit;

  Log('  stage 4/5: packages_all (packages via ppcross386)');
  if not RunMake(['packages_all',     'FPC=' + Pp] + Common, 'packages_all (i386-linux, ~3 min)') then Exit;
  Log('  stage 5/5: packages_install');
  if not RunMake(['packages_install', 'FPC=' + Pp] + Common, 'packages_install (i386-linux)') then Exit;

  Log('--- Cross-compile to i386-linux ready ---');
  Result := True;
end;

function TInstallThread.StepRemoveCrossLinux32FromLinux: Boolean;
begin
  Result := True;  // best-effort
  var UnitsDir := HostFpcUnitsDir + 'i386-linux';

  Log('Removing cross compiler i386-linux');
  Progress(-1, 'Removing i386-linux');
  if DirectoryExists(UnitsDir) then begin
    Log('  ' + UnitsDir);
    RemoveDir(UnitsDir);
  end;
  // We deliberately don't remove ppcross386 here -- it may still be in
  // use by the i386-win32 target on this host.
end;

function TInstallThread.ResolveLazarusRef: string;
begin
  Result := if (not FCfg.LazLatest) and (FCfg.LazHash <> '') then FCfg.LazHash
            else FCfg.LazBranch;
end;

function TInstallThread.LazarusDir: string;
begin
  Result := IncludeTrailingPathDelimiter(FCfg.TargetDir) + 'lazarus';
end;

function TInstallThread.LazarusPcp: string;
begin
  Result := IncludeTrailingPathDelimiter(FCfg.TargetDir) + 'config_lazarus';
end;

// installs made before the rename carry the dashed folder; reuse it when
// it is there so their add-ons keep resolving. New installs get the underscore
function TInstallThread.ComponentsExtraDir: string;
begin
  var Legacy := IncludeTrailingPathDelimiter(FCfg.TargetDir) + 'components-extra';
  if DirectoryExists(Legacy) then Exit(Legacy);
  Result := IncludeTrailingPathDelimiter(FCfg.TargetDir) + 'components_extra';
end;

function TInstallThread.StepDownloadLazarusSource: Boolean;
begin
  Result := False;
  var Ref        := ResolveLazarusRef;
  var Url        := LAZARUS_SOURCE_URL_PREFIX + Ref;
  var ZipFile    := IncludeTrailingPathDelimiter(GetTempDir) + 'lazarus-source.zip';
  var Target     := LazarusDir;
  // a hidden temp parent so FindOnlyTopDir works regardless of what else
  // sits next to the install dir (fpc, fpc322, src, ...)
  var TempParent := IncludeTrailingPathDelimiter(FCfg.TargetDir) + '.lazarus-extract';

  if DirectoryExists(Target) then removeDirVerbose(Target, 0, 10);
  if DirectoryExists(TempParent) then
    RemoveDir(TempParent);
  ForceDirectories(TempParent);

  Log('Downloading lazarus source (ref=' + Ref + ')');
  Log('  URL: ' + Url);
  Progress(0, 'Downloading lazarus source...');
  if not DownloadFile(Url, ZipFile, @Progress) then begin
    FErrorMsg := 'lazarus download failed';
    Exit;
  end;

  Log('Extracting lazarus source');
  Progress(0, 'Extracting lazarus source...');
  if not ExtractZip(ZipFile, TempParent, @Progress) then begin
    FErrorMsg := 'lazarus extract failed';
    Exit;
  end;
  DeleteFile(ZipFile);

  var ExtractedTop := FindOnlyTopDir(TempParent);
  if ExtractedTop = '' then begin
    FErrorMsg := 'unexpected lazarus archive layout (no single top dir)';
    Exit;
  end;
  if not RenameFile(IncludeTrailingPathDelimiter(TempParent) + ExtractedTop, Target) then begin
    FErrorMsg := 'cannot rename ' + ExtractedTop + ' to lazarus';
    Exit;
  end;
  RemoveDir(TempParent);

  Log('Lazarus source ready: ' + Target);
  Result := True;
end;

const
  // Packages installed into the IDE statically. Base packages first
  // reduces dep churn (lazbuild resolves but is faster on a clean
  // queue). Paths relative to <lazarus>\.
  LAZ_BASE_PACKAGES: array[0..19] of string = (
    'components\lazcontrols\design\lazcontroldsgn.lpk', 'components\datetimectrls\datetimectrls.lpk', 'components\datetimectrls\design\datetimectrlsdsgn.lpk', 'components\sdf\sdflaz.lpk',
    'components\codetools\ide\cody.lpk', 'components\projecttemplates\projtemplates.lpk', 'components\sqldb\sqldblaz.lpk', 'components\memds\memdslaz.lpk',
    'components\tdbf\dbflaz.lpk', 'components\fpcunit\ide\fpcunitide.lpk', 'components\fpcunit\testinsight\laztestinsight.lpk', 'components\daemon\lazdaemon.lpk',
    'components\leakview\leakview.lpk', 'components\tachart\tachartlazaruspkg.lpk', 'components\jcf2\IdePlugin\lazarus\jcfidelazarus.lpk', 'components\chmhelp\packages\help\lhelpcontrolpkg.lpk',
    'components\chmhelp\packages\idehelp\chmhelppkg.lpk', 'components\instantfpc\instantfpclaz.lpk', 'components\externhelp\externhelp.lpk', 'components\synedit\design\syneditdsgn.lpk');

  // Docked IDE. anchordocking added as link only; its dsgn package
  // pulls it in for IDE static linkage.
  LAZ_DOCKED_LINK_ONLY = 'components\anchordocking\anchordocking.lpk';
  LAZ_DOCKED_PACKAGES: array[0..1] of string = (
    'components\anchordocking\design\anchordockingdsgn.lpk', 'components\dockedformeditor\dockedformeditor.lpk');

  // stock lazarus minimap
  LAZ_MINIMAP_PACKAGES: array[0..0] of string = (
    'components\minimap\lazminimap.lpk');

  // the fork's own minimap, shipped inside the lazarus checkout
  LAZ_UNLEASHED_MINIMAP_PACKAGES: array[0..0] of string = (
    'components\unleashedminimap\unleashedminimap.lpk');

  // Optional CPU-View add-on lives outside the lazarus checkout to keep
  // the lazarus repo small (sources are downloaded on demand from the
  // components-v1 release into <install>/components_extra/). FWHexView
  // ships its design-time .lpk under a single name on all platforms;
  // CPUView has a per-platform .lpk because the runtime pulls in
  // platform-specific debugger glue (Windows API vs ptrace/lldb).
  // Paths here are relative to ComponentsExtraDir; AddPackage prepends LazarusDir
  // which is wrong for these -- the wired-up loop below uses absolute
  // paths via a helper instead.
  COMPONENTS_FWHEX_RUNTIME_LPK = 'FWHexView\FWHexView.LCL.lpk';
  COMPONENTS_FWHEX_DESIGN_LPK  = 'FWHexView\FWHexView_D.LCL.lpk';
  // Host-platform-specific CPUView design-time .lpk filename. The runtime
  // pieces live inside the same .lpk -- there is no separate runtime/design
  // split for CPUView. Selection is forced at the host level here because
  // the .lpk explicitly carries the target triple in its name.
{$ifdef WINDOWS}
  COMPONENTS_CPUVIEW_LPK = 'CPUView\CPUView_win_x86_64_D.lpk';
{$endif}
{$ifdef LINUX}
  COMPONENTS_CPUVIEW_LPK = 'CPUView\CPUView_lin_x86_64_D.lpk';
{$endif}

  // ToggleDisplayAffinity ships a single .lpk at the zip root (no per-
  // platform variants). The const exists on every host so callers can
  // reference it without ifdef, but the only caller that touches disk
  // is inside a {$ifdef WINDOWS} block.
  COMPONENTS_TOGGLE_LPK = 'ToggleDisplayAffinity\toggledisplayaffinity.lpk';

  // MetaDarkStyle ships its runtime + design-time .lpk side by side at
  // the zip root. Both are LCL-based so they compile on any LCL target;
  // no per-platform variant.
  COMPONENTS_METADARK_RUNTIME_LPK = 'MetaDarkStyle\metadarkstyle.lpk';
  COMPONENTS_METADARK_DESIGN_LPK  = 'MetaDarkStyle\metadarkstyledsgn.lpk';

function TInstallThread.RunLazbuild(const Args: array of string;
  const StepLabel: string): Boolean;
begin
  var LazbuildExe := IncludeTrailingPathDelimiter(LazarusDir) + 'lazbuild' + ExeExt;
  // Linux fpc post-install splits compiler binary (lib/fpc/<ver>/) from
  // user-facing wrappers + fpcmkcfg (bin/) -- prepend both so lazbuild's
  // PATH-based fpc.exe discovery finds the right wrapper / binary.
{$ifdef WINDOWS}
  var PathPrefix  := HostFpcBinDir + PathSeparator + BootstrapBinDir;
{$endif}
{$ifdef LINUX}
  var PathPrefix  := HostFpcUtilDir + PathSeparator + HostFpcBinDir;
{$endif}

  // every lazbuild invocation gets the same boilerplate so package and
  // IDE builds agree on pcp/cpu/os/lazarusdir
  var ArgsArr: array of string;
  begin
    var ExtArgs := autofree TStringList.Create;
    ExtArgs.Add('--pcp=' + LazarusPcp);
    ExtArgs.Add('--lazarusdir=' + LazarusDir);
    ExtArgs.Add('--cpu=x86_64');
    ExtArgs.Add('--os=' + HostTargetOs);
{$ifdef LINUX}
    // pin the widget set: lazbuild otherwise takes whatever the sources
    // default to, and a default flip upstream silently changes what the
    // IDE links against mid-release
    ExtArgs.Add('--ws=gtk3');
{$endif}
    for var i := Low(Args) to High(Args) do
      ExtArgs.Add(Args[i]);
    SetLength(ArgsArr, ExtArgs.Count);
    for var i := 0 to ExtArgs.Count - 1 do
      ArgsArr[i] := ExtArgs[i];
  end;

  Log('Running: lazbuild ' + StepLabel);
  Progress(-1, StepLabel);
  var ExitCode := RunStream(LazbuildExe, ArgsArr, LazarusDir, PathPrefix, @OnMakeLine);
  Result := ExitCode = 0;
  if not Result then begin
    FErrorMsg := StepLabel + ' failed (lazbuild exit=' + IntToStr(ExitCode) + ')';
    Log('  ' + FErrorMsg);
  end;
end;

function TInstallThread.AddPackage(const LpkRel: string;
  LinkOnly: Boolean): Boolean;
begin
  var LpkPath := IncludeTrailingPathDelimiter(LazarusDir) + LpkRel;
  var Mode    := if LinkOnly then '--add-package-link' else '--add-package';
  Result := RunLazbuild([Mode, LpkPath], Mode + ' ' + ExtractFileName(LpkRel));
end;

// Same as AddPackage but for packages outside LazarusDir (the optional
// add-ons under <TargetDir>/components_extra/). lazbuild itself does
// not care where the .lpk lives, only that it can resolve required
// packages -- which it does via the per-user pcp's known-package list,
// populated by `--add-package` / `--add-package-link` itself.
function TInstallThread.AddPackageAbs(const LpkAbs: string;
  LinkOnly: Boolean): Boolean;
begin
  var Mode := if LinkOnly then '--add-package-link' else '--add-package';
  Result := RunLazbuild([Mode, LpkAbs], Mode + ' ' + ExtractFileName(LpkAbs));
end;

// Register the CPU-View triple: FWHexView.LCL (runtime dep, link-only so
// it does not end up statically linked into the IDE -- the design-time
// .lpk does), FWHexView_D.LCL (design-time, IDE component), and the
// host-platform CPUView_<plat>_D.lpk (design-time, IDE plugin). Order
// matters: lazbuild resolves RequiredPkgs against the known-packages
// list, so the runtime dep must be registered before its dependents.
function TInstallThread.RegisterCPUViewPackages: Boolean;

  // The COMPONENTS_*_LPK constants are authored with backslashes so the
  // strings look natural on Windows. On Linux backslash is a legal
  // filename character (FileExists treats 'comp\foo' as a literal name,
  // not as a directory traversal), so we must normalize to the host's
  // separator before any disk lookup. lazbuild itself is more forgiving
  // -- it parses .lpk paths through its own canonicalizer -- but our
  // pre-flight FileExists check sits in front of lazbuild and needs the
  // real on-disk path.
  function HostPath(const P: string): string;
  begin
    Result := StringReplace(P, '\', DirectorySeparator, [rfReplaceAll]);
  end;

begin
  Result := False;
  var Base := IncludeTrailingPathDelimiter(ComponentsExtraDir);
  var FwhexRt   := HostPath(Base + COMPONENTS_FWHEX_RUNTIME_LPK);
  var FwhexDsgn := HostPath(Base + COMPONENTS_FWHEX_DESIGN_LPK);
  var Cpuview   := HostPath(Base + COMPONENTS_CPUVIEW_LPK);

  if not FileExists(FwhexRt) then begin
    FErrorMsg := 'CPU-View addon: missing ' + FwhexRt +
                 ' (was StepDownloadComponents skipped?)';
    Log('  ' + FErrorMsg);
    Exit;
  end;
  if not FileExists(FwhexDsgn) then begin
    FErrorMsg := 'CPU-View addon: missing ' + FwhexDsgn;
    Log('  ' + FErrorMsg);
    Exit;
  end;
  if not FileExists(Cpuview) then begin
    FErrorMsg := 'CPU-View addon: missing ' + Cpuview +
                 ' (no .lpk for this host platform?)';
    Log('  ' + FErrorMsg);
    Exit;
  end;

  Log('Registering FWHexView runtime (link-only)');
  if not AddPackageAbs(FwhexRt, True) then Exit;
  Log('Registering FWHexView design-time');
  if not AddPackageAbs(FwhexDsgn) then Exit;
  Log('Registering CPUView design-time');
  if not AddPackageAbs(Cpuview) then Exit;
  Result := True;
end;

// Tear down what RegisterCPUViewPackages wrote into the IDE config.
// Order is the reverse of registration: design-time first (because
// removing the runtime first would leave a dangling RequiredPkgs link
// in the design-time entries until the next IDE rebuild).
procedure TInstallThread.UnregisterCPUViewPackages;
begin
  // Package NAMES (not file paths). These come from the <Name Value="..."/>
  // of each .lpk file -- not the on-disk filename. Hardcoded so a future
  // version change in the .lpk filename does not silently break removal.
  UnregisterIdePackage('CPUView_win_x86_64_D');
  UnregisterIdePackage('CPUView_lin_x86_64_D');
  UnregisterIdePackage('CPUView_lin_aarch64_D');
  UnregisterIdePackage('FWHexView_D.LCL');
  UnregisterIdePackage('FWHexView.LCL');
end;

// Register the MetaDarkStyle pair: MetaDarkStyle (runtime, link-only --
// the actual dark theme logic) then metadarkstyledsgn (design-time, the
// IDE plugin). Order matters because the design-time .lpk's
// RequiredPkgs lists MetaDarkStyle by name; lazbuild resolves that
// against the known-packages list and rejects design-time registration
// if the runtime isn't in there yet.
function TInstallThread.RegisterMetaDarkStylePackages: Boolean;

  function HostPath(const P: string): string;
  begin
    Result := StringReplace(P, '\', DirectorySeparator, [rfReplaceAll]);
  end;

begin
  Result := False;
  var Base := IncludeTrailingPathDelimiter(ComponentsExtraDir);
  var RuntimeLpk := HostPath(Base + COMPONENTS_METADARK_RUNTIME_LPK);
  var DesignLpk  := HostPath(Base + COMPONENTS_METADARK_DESIGN_LPK);

  if not FileExists(RuntimeLpk) then begin
    FErrorMsg := 'MetaDarkStyle addon: missing ' + RuntimeLpk +
                 ' (was StepDownloadComponents skipped?)';
    Log('  ' + FErrorMsg);
    Exit;
  end;
  if not FileExists(DesignLpk) then begin
    FErrorMsg := 'MetaDarkStyle addon: missing ' + DesignLpk;
    Log('  ' + FErrorMsg);
    Exit;
  end;

  Log('Registering MetaDarkStyle runtime (link-only)');
  if not AddPackageAbs(RuntimeLpk, True) then Exit;
  Log('Registering MetaDarkStyle design-time');
  if not AddPackageAbs(DesignLpk) then Exit;
  Result := True;
end;

// Tear down what RegisterMetaDarkStylePackages wrote. Design-time
// first so the runtime's removal does not leave a dangling
// RequiredPkgs reference in the design-time entries between this
// step and the next `lazbuild --build-ide`.
procedure TInstallThread.UnregisterMetaDarkStylePackages;
begin
  UnregisterIdePackage('metadarkstyledsgn');
  UnregisterIdePackage('MetaDarkStyle');
end;

// The minimap paints the slice of the file the editor shows in a system
// colour, and reads that colour once at startup. clBackground (the desktop
// colour) only sits well under MetaDarkStyle, so a light IDE gets clMenu
// instead. Written before the IDE first runs; TXMLConfig lays out the file
// exactly as the minimap's own TConfigStorage would.
procedure TInstallThread.WriteMinimapConfig;
const
  // TColor system colours: SYS_COLOR_BASE ($80000000) or the COLOR_* index
  CL_BACKGROUND = Integer($80000001);
  CL_MENU       = Integer($80000004);
begin
  var Dir := IncludeTrailingPathDelimiter(LazarusPcp);
  if not ForceDirectories(Dir) then Exit;

  var Color := CL_MENU;
  var Name := 'clMenu';
  if FCfg.InstallMetaDarkStyle then begin
    Color := CL_BACKGROUND;
    Name := 'clBackground';
  end;

  var Cfg := autofree TXMLConfig.Create(nil);
  Cfg.Filename := Dir + 'minimap.xml';
  Cfg.SetValue('ViewWindowColor', Color);
  Cfg.Flush;
  Log('  minimap view window colour set to ' + Name);
end;

// Add a "CPU-View" entry to the IDE editor toolbar in
// <pcp>/environmentoptions.xml. The IDE stores the toolbar layout
// per-desktop inside <Desktops>/<Desktop{N}>/<EditorToolBarOptions>,
// with a numbered <Button{i} Name="..."/> sequence and a Count attribute.
// On a fresh install the IDE has not yet been launched, so the section
// does not exist -- we silently skip in that case (the IDE will create
// the default toolbar on first run, and a subsequent installer re-run
// with CPU-View still selected will then inject the button).
procedure TInstallThread.RegisterCPUViewToolbarButton;
const
  ButtonName: string = 'CPU-View';
begin
  var XmlPath := IncludeTrailingPathDelimiter(LazarusPcp) + 'environmentoptions.xml';
  if not FileExists(XmlPath) then Exit;

  var Cfg := autofree TXMLConfig.Create(nil);
  Cfg.Filename := XmlPath;
  // <Desktops> is a sibling of <EnvironmentOptions> under <CONFIG>, not a
  // child of it. The path must root at "Desktops/" -- using the
  // "EnvironmentOptions/Desktops/..." prefix silently returns 0 via
  // TXMLConfig's missing-path default and the function becomes a no-op.
  var DesktopsCount: Integer := Cfg.GetValue('Desktops/Count', 0);
  if DesktopsCount = 0 then Exit;

  var Touched: Boolean := False;
  for var d := 1 to DesktopsCount do begin
    var Base := 'Desktops/Desktop' + IntToStr(d) +
                '/EditorToolBarOptions/';
    var Cnt: Integer := Cfg.GetValue(Base + 'Count', 0);
    // section absent -> nothing to add; the IDE will write its default
    // toolbar block on first save and a later installer run can append
    // the button then. This is the documented "skip if section missing"
    // behavior chosen at design time.
    if Cnt = 0 then Continue;

    var EmptyStr: string := '';
    var AlreadyThere: Boolean := False;
    for var i := 1 to Cnt do
      if Cfg.GetValue(Base + 'Button' + IntToStr(i) + '/Name', EmptyStr) =
         ButtonName then begin
        AlreadyThere := True;
        Break;
      end;
    if AlreadyThere then Continue;

    Cfg.SetValue(Base + 'Button' + IntToStr(Cnt + 1) + '/Name', ButtonName);
    Cfg.SetValue(Base + 'Count', Cnt + 1);
    Touched := True;
    Log('  added CPU-View toolbar button to Desktop' + IntToStr(d) +
        ' (now ' + IntToStr(Cnt + 1) + ' buttons)');
  end;

  if Touched then Cfg.Flush;
end;

// Reverse of RegisterCPUViewToolbarButton: drop the CPU-View entry from
// every desktop's editor toolbar, shifting later buttons down by one and
// decrementing Count. No-op if the button isn't present.
procedure TInstallThread.UnregisterCPUViewToolbarButton;
const
  ButtonName: string = 'CPU-View';
begin
  var XmlPath := IncludeTrailingPathDelimiter(LazarusPcp) + 'environmentoptions.xml';
  if not FileExists(XmlPath) then Exit;

  var Cfg := autofree TXMLConfig.Create(nil);
  Cfg.Filename := XmlPath;
  // Path rooted at "Desktops/" -- see RegisterCPUViewToolbarButton above
  // for why the "EnvironmentOptions/" prefix is wrong here.
  var DesktopsCount: Integer := Cfg.GetValue('Desktops/Count', 0);
  if DesktopsCount = 0 then Exit;

  var Touched: Boolean := False;
  for var d := 1 to DesktopsCount do begin
    var Base := 'Desktops/Desktop' + IntToStr(d) +
                '/EditorToolBarOptions/';
    var Cnt: Integer := Cfg.GetValue(Base + 'Count', 0);
    if Cnt = 0 then Continue;

    var EmptyStr: string := '';
    var Found: Integer := -1;
    for var i := 1 to Cnt do
      if Cfg.GetValue(Base + 'Button' + IntToStr(i) + '/Name', EmptyStr) =
         ButtonName then begin
        Found := i;
        Break;
      end;
    if Found < 1 then Continue;

    // shift Button{Found+1..Cnt} down by one, drop the last slot.
    for var i := Found to Cnt - 1 do
      Cfg.SetValue(Base + 'Button' + IntToStr(i) + '/Name', Cfg.GetValue(Base + 'Button' + IntToStr(i + 1) + '/Name', EmptyStr));
    Cfg.DeletePath(Base + 'Button' + IntToStr(Cnt));
    Cfg.SetValue(Base + 'Count', Cnt - 1);
    Touched := True;
    Log('  removed CPU-View toolbar button from Desktop' + IntToStr(d));
  end;

  if Touched then Cfg.Flush;
end;

function TInstallThread.StepBuildLazarus: Boolean;
begin
  Result := False;
{$ifdef WINDOWS}
  var MakeExe    := IncludeTrailingPathDelimiter(BootstrapBinDir) + 'make.exe';
  var FpcExe     := HostFpcBinDir + 'fpc' + ExeExt;
  // native fpc.exe before bootstrap so lazbuild's PATH-based compiler
  // detection picks the x86_64 wrapper; bootstrap stays for make + binutils
  var PathPrefix := HostFpcBinDir + PathSeparator + BootstrapBinDir;
{$endif}
{$ifdef LINUX}
  var MakeExe    := 'make';                    // system make
  // on Linux, `fpc` is a shell wrapper in <prefix>/bin/ that exec's
  // <prefix>/lib/fpc/<ver>/ppcx64 -- safe to pass as PP= to make.
  var FpcExe     := HostFpcUtilDir + 'fpc' + ExeExt;
  var PathPrefix := HostFpcUtilDir + PathSeparator + HostFpcBinDir;
{$endif}
  ForceDirectories(LazarusPcp);

  // the makefile spawns fpc itself, so our own -Fu/-n flags never reach it;
  // OPT is the only channel into those calls
  var CfgOpt: TStringArray := [];
  var CfgFlag := makeCfgOpt;
  if CfgFlag <> '' then CfgOpt := ['OPT=' + CfgFlag];

  Log('--- Building Lazarus IDE ---');
  Log('  source dir: ' + LazarusDir);
  Log('  PP:         ' + FpcExe);
  if CfgFlag <> '' then
    Log('  OPT:        ' + CfgFlag)
  else
    Log('  OPT:        none (cfg path has a space; PPC_CONFIG_PATH still pins it)');

  // 1. build lazbuild + LCL + minimum prereqs that the upcoming
  //    --add-package calls will need to compile each package against.
  SetStage(isLazMakelazbuild);
  Progress(-1, 'make lazbuild (LCL + lazbuild, ~3 min)');
  var ExitCode := RunStream(MakeExe, ['lazbuild', 'PP=' + FpcExe] + CfgOpt, LazarusDir, PathPrefix, @OnMakeLine);
  if ExitCode <> 0 then begin
    FErrorMsg := 'lazbuild bootstrap failed (make exit=' + IntToStr(ExitCode) + ')';
    Log('  ' + FErrorMsg);
    Exit;
  end;

  // 2. register every package with our isolated config_lazarus. lazbuild
  //    appends each to staticpackages.inc + idemake.cfg in the pcp;
  //    --build-ide later picks them up.
  SetStage(isLazPackages);
  Log('Registering base packages (' + IntToStr(Length(LAZ_BASE_PACKAGES)) + ')');
  for var i := Low(LAZ_BASE_PACKAGES) to High(LAZ_BASE_PACKAGES) do begin
    if not AddPackage(LAZ_BASE_PACKAGES[i]) then Exit;
    // smooth-fill the package-registration slice as each lpk lands
    Progress(Round((i + 1) * 100 / (Length(LAZ_BASE_PACKAGES) +
      Length(LAZ_DOCKED_PACKAGES) + Length(LAZ_MINIMAP_PACKAGES) + 1)), ExtractFileName(LAZ_BASE_PACKAGES[i]));
  end;

  Log('Registering docked-IDE packages');
  // anchordocking is a runtime package; the IDE statically links its
  // *dsgn variant which depends on the runtime. add the runtime as a
  // link only so it ends up in package list but not in staticpackages.inc.
  if not AddPackage(LAZ_DOCKED_LINK_ONLY, True) then Exit;
  for var i := Low(LAZ_DOCKED_PACKAGES) to High(LAZ_DOCKED_PACKAGES) do
    if not AddPackage(LAZ_DOCKED_PACKAGES[i]) then Exit;

  if FCfg.InstallMinimap then begin
    Log('Registering Lazarus minimap addon');
    for var i := Low(LAZ_MINIMAP_PACKAGES) to High(LAZ_MINIMAP_PACKAGES) do
      if not AddPackage(LAZ_MINIMAP_PACKAGES[i]) then Exit;
    WriteMinimapConfig;
  end
  else
    Log('Skipping Lazarus minimap addon (not selected)');

  if FCfg.InstallUnleashedMinimap then begin
    Log('Registering Unleashed minimap addon');
    for var i := Low(LAZ_UNLEASHED_MINIMAP_PACKAGES) to High(LAZ_UNLEASHED_MINIMAP_PACKAGES) do
      if not AddPackage(LAZ_UNLEASHED_MINIMAP_PACKAGES[i]) then Exit;
  end
  else
    Log('Skipping Unleashed minimap addon (not selected)');

  if FCfg.InstallCPUView then begin
    Log('Registering CPU-View addon (FWHexView + CPUView)');
    if not RegisterCPUViewPackages then Exit;
  end
  else
    Log('Skipping CPU-View addon (not selected)');

  if FCfg.InstallMetaDarkStyle then begin
    Log('Registering MetaDarkStyle addon (runtime + design-time)');
    if not RegisterMetaDarkStylePackages then Exit;
  end
  else
    Log('Skipping MetaDarkStyle addon (not selected)');

{$ifdef WINDOWS}
  if FCfg.InstallToggleAffinity then begin
    Log('Registering Toggle Display Affinity addon');
    var TogglePath := StringReplace(
      IncludeTrailingPathDelimiter(ComponentsExtraDir) + COMPONENTS_TOGGLE_LPK, '\', DirectorySeparator, [rfReplaceAll]);
    if not FileExists(TogglePath) then begin
      FErrorMsg := 'Toggle Display Affinity addon: missing ' + TogglePath +
                   ' (was StepDownloadComponents skipped?)';
      Log('  ' + FErrorMsg);
      Exit;
    end;
    if not AddPackageAbs(TogglePath) then Exit;
  end
  else
    Log('Skipping Toggle Display Affinity addon (not selected)');
{$endif}

  // 3. final IDE build linking everything from staticpackages.inc.
  //    -dKeepInstalledPackages keeps the package list around between
  //    rebuilds so a re-run of --build-ide does not silently drop them.
  //    We do not pass -dAddStaticPkgs here -- the lazarus packagesystem
  //    (ide/packages/idepackager/packagesystem.pas:2533) emits it
  //    automatically when assembling the build command, so adding it
  //    on the call line is redundant. lazbuild prints "[ NN%]" lines
  //    that OnMakeLine catches and feeds back into our progress.
  SetStage(isLazIde);
  if not RunLazbuild(
    ['--build-ide=-dKeepInstalledPackages'], 'lazbuild --build-ide (~5 min)') then Exit;

  // --build-ide builds lazarus.exe but not startlazarus, the launcher the
  // IDE re-spawns to restart itself after Tools -> Build Lazarus. Without it
  // the post-rebuild restart fails with "Cannot find Lazarus starter". Its
  // .lpi outputs to <lazarus>/startlazarus, next to lazarus.exe.
  if not RunLazbuild(
    [IncludeTrailingPathDelimiter(LazarusDir) + 'ide' + DirectorySeparator + 'startlazarus.lpi'],
    'lazbuild startlazarus') then Exit;

  // No toolbar XML touch on the fresh install path: the compiled IDE
  // already carries CPU-View as part of its default editor toolbar (the
  // Lazarus fork wires it in when the package is registered), so writing
  // anything here would just be a race against the IDE's own first-close
  // rewrite of environmentoptions.xml. Toolbar sync stays scoped to the
  // addon-delta path inside StepRebuildLazarusForAddons, where the file
  // already exists and the user genuinely flipped the addon state.

  Log('--- Lazarus ready: ' + IncludeTrailingPathDelimiter(LazarusDir) +
      'lazarus' + ExeExt + ' ---');
  Result := True;
end;

// Build lhelp, the standalone CHM viewer that chmhelppkg spawns for F1.
// Upstream gets it from `make bigide`; our lazbuild path never reaches
// that target, so the IDE would carry the help integration with nothing
// behind it. The IDE can build lhelp itself on first F1, but only when
// the install dir is writable and the user waits through it.
function TInstallThread.stepBuildLHelp: Boolean;
begin
  result := False;
  var lhelpDir := IncludeTrailingPathDelimiter(LazarusDir)+'components'+DirectorySeparator+'chmhelp'+DirectorySeparator+'lhelp'+DirectorySeparator;
  if not FileExists(lhelpDir+'lhelp.lpi') then begin
    FErrorMsg := 'lhelp.lpi not found at '+lhelpDir;
    exit;
  end;
  if FileExists(lhelpDir+'lhelp'+ExeExt) then begin
    Log('lhelp already built, skipping');
    exit(True);
  end;
  // lhelp.lpi requires TurboPowerIPro, which is not in the IDE package
  // set; register it link-only or lazbuild fails to resolve the dep.
  if not AddPackage('components'+DirectorySeparator+'turbopower_ipro'+DirectorySeparator+'turbopoweripro.lpk', True) then exit;
  result := RunLazbuild([lhelpDir+'lhelp.lpi'], 'lazbuild lhelp (CHM help viewer)');
end;

// Fetch the CHM documentation bundle into <lazarus>\docs\chm, the path
// chmhelppkg searches by default. The SHA pin covers the transport; the
// magic checks stay because they also catch a re-tagged release asset,
// and lhelp hands whatever sits in docs\chm to the CHM reader.
function TInstallThread.stepInstallHelpFiles: Boolean;

  // compare the first Length(magic) bytes of the file against magic
  function hasMagic(const path, magic: string): Boolean;
  begin
    result := False;
    var buf: array[0..7] of Byte;
    if Length(magic) > SizeOf(buf) then exit;
    try
      var f := autofree TFileStream.Create(path, fmOpenRead or fmShareDenyWrite);
      if f.Read(buf[0], Length(magic)) <> Length(magic) then exit;
    except
      exit;
    end;
    for var i := 1 to Length(magic) do
      if buf[i-1] <> Ord(magic[i]) then exit;
    result := True;
  end;

begin
  result := False;
  var docsDir := IncludeTrailingPathDelimiter(LazarusDir)+'docs'+DirectorySeparator;
  var chmDir  := docsDir+'chm'+DirectorySeparator;
  // rtl + lcl are the two the IDE resolves F1 against; both present means
  // a previous run already did this and a re-install has nothing to do
  if FileExists(chmDir+'rtl.chm') and FileExists(chmDir+'lcl.chm') then begin
    Log('CHM documentation already present in '+chmDir+', skipping download');
    exit(True);
  end;

  var zipFile := IncludeTrailingPathDelimiter(GetTempDir)+'lazarus-doc-chm.zip';
  if not DownloadAndVerify(DOCS_CHM_URL, DOCS_CHM_SHA, zipFile, 'CHM documentation') then exit;
  if not hasMagic(zipFile, 'PK') then begin
    DeleteFile(zipFile);
    FErrorMsg := 'CHM documentation download is not a zip';
    exit;
  end;

  Log('Extracting CHM documentation to '+docsDir);
  Progress(-1, 'Extracting CHM documentation');
  ForceDirectories(docsDir);
  var extracted := ExtractZip(zipFile, docsDir, @Progress);
  DeleteFile(zipFile);
  if not extracted then begin
    FErrorMsg := 'CHM documentation extract failed';
    exit;
  end;

  // ITSF is the CHM container signature. Anything else under docs\chm
  // would be handed to lhelp as help content, so drop it.
  var rejected := 0;
  var sr: TSearchRec;
  if FindFirst(chmDir+'*.chm', faAnyFile, sr) = 0 then begin
    repeat
      if (sr.Attr and faDirectory) <> 0 then continue;
      if hasMagic(chmDir+sr.Name, 'ITSF') then continue;
      Log('  rejected '+sr.Name+': not a CHM file');
      DeleteFile(chmDir+sr.Name);
      Inc(rejected);
    until FindNext(sr) <> 0;
    FindClose(sr);
  end;

  if not (FileExists(chmDir+'rtl.chm') and FileExists(chmDir+'lcl.chm')) then begin
    FErrorMsg := 'CHM documentation incomplete: rtl.chm / lcl.chm missing after extract';
    exit;
  end;
  Log('CHM documentation installed in '+chmDir+(if rejected > 0 then ' ('+IntToStr(rejected)+' file(s) rejected)' else ''));
  result := True;
end;

// Help viewer + docs, both optional: a failure is logged and the pipeline
// carries on. Runs ahead of StepCreateShortcuts so the yellow "start the
// IDE from the shortcut" banner stays the last thing in the log.
procedure TInstallThread.runHelpSteps;
begin
  if not FCfg.InstallLazarus then exit;
  if not FileExists(IncludeTrailingPathDelimiter(LazarusDir)+'lazarus'+ExeExt) then exit;
  SetStage(isHelp);
  if not stepBuildLHelp then begin
    Log('WARNING: help viewer not built: '+FErrorMsg);
    FErrorMsg := '';
  end;
  if not FCfg.InstallHelpFiles then exit;
  if not stepInstallHelpFiles then begin
    Log('WARNING: CHM documentation not installed: '+FErrorMsg);
    FErrorMsg := '';
  end;
end;

// Edit Lazarus's miscellaneousoptions.xml + packagefiles.xml in-place
// to drop the named package's registration. After this and a
// `lazbuild --build-ide`, the resulting IDE binary no longer statically
// links the package and the IDE no longer lists it in known-packages.
procedure TInstallThread.UnregisterIdePackage(const PkgName: string);

  procedure RemoveIndexedItem(const XmlPath, KeyStart, ValuePath: string);
  begin
    if not FileExists(XmlPath) then Exit;
    var Cfg := autofree TXMLConfig.Create(nil);
    Cfg.Filename := XmlPath;
    var Cnt: Integer := Cfg.GetValue(KeyStart + 'Count', 0);
    var Found: Integer := -1;
    var EmptyStr: string := '';
    for var i := 1 to Cnt do
      if SameText(Cfg.GetValue(KeyStart + 'Item' + IntToStr(i) + '/' + ValuePath, EmptyStr), PkgName) then begin
        Found := i;
        Break;
      end;
    if Found < 1 then Exit;
    // shift remaining items down by one
    for var i := Found to Cnt - 1 do
      Cfg.SetValue(KeyStart + 'Item' + IntToStr(i) + '/' + ValuePath, Cfg.GetValue(KeyStart + 'Item' + IntToStr(i+1) + '/' + ValuePath, EmptyStr));
    Cfg.DeletePath(KeyStart + 'Item' + IntToStr(Cnt));
    Cfg.SetValue(KeyStart + 'Count', Cnt - 1);
    Cfg.Flush;
  end;

begin
  var Pcp := IncludeTrailingPathDelimiter(LazarusPcp);
  // miscellaneousoptions.xml controls what gets statically linked into
  // the IDE on `lazbuild --build-ide`.
  RemoveIndexedItem(Pcp + 'miscellaneousoptions.xml', 'MiscellaneousOptions/BuildLazarusOptions/StaticAutoInstallPackages/', 'Value');
  // packagefiles.xml is the IDE's known-packages list (used by
  // Package menu, Open Package... etc).
  RemoveIndexedItem(Pcp + 'packagefiles.xml', 'UserPkgLinks/', 'Name/Value');
end;

// "Reinstall" with a flipped addon checkbox does not need to redo the
// whole Lazarus install; just (a) run lazbuild --add-package on the
// newly-ticked addons OR remove the registration of the unticked ones,
// and (b) re-run --build-ide so the resulting binary statically links
// the new package set.
function TInstallThread.StepRebuildLazarusForAddons: Boolean;
begin
  Result := False;
  var Prev := ReadManifest(FCfg.TargetDir);
  SetStage(isLazPackages);

  if FCfg.InstallMinimap and (not Prev.InstallMinimap) then begin
    Log('Adding Lazarus minimap addon');
    for var i := Low(LAZ_MINIMAP_PACKAGES) to High(LAZ_MINIMAP_PACKAGES) do
      if not AddPackage(LAZ_MINIMAP_PACKAGES[i]) then Exit;
  end
  else if (not FCfg.InstallMinimap) and Prev.InstallMinimap then begin
    Log('Removing Lazarus minimap addon');
    UnregisterIdePackage('lazminimap');
  end;

  if FCfg.InstallUnleashedMinimap and (not Prev.InstallUnleashedMinimap) then begin
    Log('Adding Unleashed minimap addon');
    for var i := Low(LAZ_UNLEASHED_MINIMAP_PACKAGES) to High(LAZ_UNLEASHED_MINIMAP_PACKAGES) do
      if not AddPackage(LAZ_UNLEASHED_MINIMAP_PACKAGES[i]) then Exit;
  end
  else if (not FCfg.InstallUnleashedMinimap) and Prev.InstallUnleashedMinimap then begin
    Log('Removing Unleashed minimap addon');
    UnregisterIdePackage('UnleashedMinimap');
  end;

  // the colour depends on the MetaDarkStyle box too, so either box moving
  // rewrites it
  if FCfg.InstallMinimap and ((not Prev.InstallMinimap) or (FCfg.InstallMetaDarkStyle <> Prev.InstallMetaDarkStyle)) then
    WriteMinimapConfig;

  if FCfg.InstallCPUView and (not Prev.InstallCPUView) then begin
    Log('Adding CPU-View addon');
    // sources may already be cached from a prior tick-then-untick run,
    // but a fresh tick still has to fetch them if components_extra/ was
    // wiped between runs. Hook the download here so re-installs don't
    // require running the full bootstrap path again.
    SetStage(isLazComponents);
    if not StepDownloadComponents then Exit;
    SetStage(isLazPackages);
    if not RegisterCPUViewPackages then Exit;
    // Toolbar button: the IDE has run at least once at this point
    // (Prev.InstallCPUView=False but Lazarus is built and Prev is from
    // a manifest of an existing install), so environmentoptions.xml
    // should already carry EditorToolBarOptions blocks the IDE wrote on
    // first launch -- the helper picks them up and appends CPU-View.
    RegisterCPUViewToolbarButton;
  end
  else if (not FCfg.InstallCPUView) and Prev.InstallCPUView then begin
    Log('Removing CPU-View addon');
    UnregisterCPUViewPackages;
    UnregisterCPUViewToolbarButton;
  end;

  if FCfg.InstallMetaDarkStyle and (not Prev.InstallMetaDarkStyle) then begin
    Log('Adding MetaDarkStyle addon');
    SetStage(isLazComponents);
    if not StepDownloadComponents then Exit;
    SetStage(isLazPackages);
    if not RegisterMetaDarkStylePackages then Exit;
  end
  else if (not FCfg.InstallMetaDarkStyle) and Prev.InstallMetaDarkStyle then begin
    Log('Removing MetaDarkStyle addon');
    UnregisterMetaDarkStylePackages;
  end;

{$ifdef WINDOWS}
  // Toggle Display Affinity delta: same skeleton as CPU-View but a
  // single-package add/remove (no runtime dependency, no toolbar button
  // -- the plugin installs itself as a Window menu entry which the IDE
  // picks up directly from the registered design-time package).
  if FCfg.InstallToggleAffinity and (not Prev.InstallToggleAffinity) then begin
    Log('Adding Toggle Display Affinity addon');
    SetStage(isLazComponents);
    if not StepDownloadComponents then Exit;
    SetStage(isLazPackages);
    var TogglePath := StringReplace(
      IncludeTrailingPathDelimiter(ComponentsExtraDir) + COMPONENTS_TOGGLE_LPK, '\', DirectorySeparator, [rfReplaceAll]);
    if not AddPackageAbs(TogglePath) then Exit;
  end
  else if (not FCfg.InstallToggleAffinity) and Prev.InstallToggleAffinity then begin
    Log('Removing Toggle Display Affinity addon');
    UnregisterIdePackage('ToggleDisplayAffinity');
  end;
{$endif}

  SetStage(isLazIde);
  if not RunLazbuild(
    ['--build-ide=-dKeepInstalledPackages'], 'lazbuild --build-ide (~5 min)') then Exit;

  Log('--- Lazarus IDE rebuilt with new addon set ---');
  Result := True;
end;

// write Content to FilePath, return false on error and stash the message.
function TInstallThread.WriteConfigFile(const FilePath, Content: string): Boolean;
begin
  Result := False;
  ForceDirectories(ExtractFilePath(FilePath));
  try
    var Stream := autofree TFileStream.Create(FilePath, fmCreate);
    if Length(Content) > 0 then
      Stream.WriteBuffer(Content[1], Length(Content));
    Result := True;
  except
    on E: Exception do begin
      FErrorMsg := 'cannot write ' + FilePath + ': ' + E.Message;
      Log('  ' + FErrorMsg);
    end;
  end;
end;

function TInstallThread.StepGenerateLazarusConfig: Boolean;
begin
  Result := False;
  Progress(-1, 'Writing Lazarus config');
  ForceDirectories(LazarusPcp);
  var ProjectsDir := IncludeTrailingPathDelimiter(FCfg.TargetDir) + 'projects';
  ForceDirectories(ProjectsDir);

  var Xml := ENV_OPTIONS_TEMPLATE;
{$ifdef WINDOWS}
  var MakePath := IncludeTrailingPathDelimiter(BootstrapBinDir) + 'make' + ExeExt;
  // on Linux the FPC bootstrap zip has no make; the IDE picks up the
  // system /usr/bin/make from PATH at runtime if MakeFilename is empty
  // -- actually leaving the default 'make' in environmentoptions.xml is
  // what Lazarus prefers there.
{$endif}
{$ifdef LINUX}
  var MakePath := 'make';
{$endif}
  // FPC compiler path Lazarus uses for code-completion + project builds.
  // On Linux the `fpc` shell wrapper in <prefix>/bin/ is what users
  // normally point IDEs at; it dispatches to ppcx64.
  var FpcCompilerPath :=
{$ifdef WINDOWS}
    HostFpcBinDir + 'fpc' + ExeExt;
{$endif}
{$ifdef LINUX}
    HostFpcUtilDir + 'fpc' + ExeExt;
{$endif}
  Xml := StringReplace(Xml, '%LAZ%',      LazarusDir,                          [rfReplaceAll]);
  Xml := StringReplace(Xml, '%FPC%',      FpcCompilerPath,                     [rfReplaceAll]);
  Xml := StringReplace(Xml, '%FPCSRC%',   MakeWorkDir,                         [rfReplaceAll]);
  Xml := StringReplace(Xml, '%MAKE%',     MakePath,                            [rfReplaceAll]);
  Xml := StringReplace(Xml, '%PROJECTS%', ProjectsDir,                         [rfReplaceAll]);

  Log('Writing ' + LazarusPcp + '\environmentoptions.xml');
  if not WriteConfigFile(IncludeTrailingPathDelimiter(LazarusPcp) +
    'environmentoptions.xml', Xml) then Exit;

  Log('Writing ' + LazarusPcp + '\anchordockingoptions.xml');
  if not WriteConfigFile(IncludeTrailingPathDelimiter(LazarusPcp) +
    'anchordockingoptions.xml', ANCHOR_DOCKING_OPTIONS) then Exit;

  Log('Writing ' + LazarusPcp + '\dockedformeditoroptions.xml');
  if not WriteConfigFile(IncludeTrailingPathDelimiter(LazarusPcp) +
    'dockedformeditoroptions.xml', DOCKED_FORM_EDITOR_OPTIONS) then Exit;

  Log('Writing ' + LazarusPcp + '\debuggeroptions.xml');
  if not WriteConfigFile(IncludeTrailingPathDelimiter(LazarusPcp) +
    'debuggeroptions.xml', DEBUGGER_OPTIONS) then Exit;

  var EditorOptPath := IncludeTrailingPathDelimiter(LazarusPcp) + 'editoroptions.xml';
  if FileExists(EditorOptPath) then
    Log('editoroptions.xml already present, leaving it alone')
  else begin
    Log('Writing ' + LazarusPcp + '\editoroptions.xml');
    if not WriteConfigFile(EditorOptPath, EDITOR_OPTIONS) then Exit;
  end;

  Result := True;
end;

function TInstallThread.StepCreateShortcuts: Boolean;
begin
  Result := False;
  var TargetExe := IncludeTrailingPathDelimiter(LazarusDir) + 'lazarus' + ExeExt;
  // --pcp loads our isolated config_lazarus instead of the default per-user
  // dir (%LOCALAPPDATA%\lazarus on Windows, ~/.lazarus on Linux)
  var Args := '--pcp="' + LazarusPcp + '"';
  var Name := 'Launch Unleashed IDE';
  var Dir  := ExcludeTrailingPathDelimiter(FCfg.TargetDir);
  var madeDesktop := False;
  var madeFolder  := False;

  if FCfg.MakeDesktopShortcut then begin
    Log('Creating desktop shortcut: ' + Name);
    Progress(-1, 'Creating desktop shortcut');
    if not CreateDesktopShortcut(TargetExe, Args, Name) then begin
      FErrorMsg := 'failed to create desktop shortcut';
      Log('  ' + FErrorMsg);
      Exit;
    end;
    madeDesktop := True;
    Log('Shortcut placed on the desktop.');
  end;

  if FCfg.MakeFolderShortcut then begin
    Log('Creating install-folder shortcut in ' + Dir);
    Progress(-1, 'Creating install-folder shortcut');
    if not CreateFolderShortcut(Dir, TargetExe, Args, Name) then begin
      FErrorMsg := 'failed to create install-folder shortcut';
      Log('  ' + FErrorMsg);
      Exit;
    end;
    madeFolder := True;
    Log('Shortcut placed in ' + Dir);
  end;

  // marker phrase 'IMPORTANT' is picked up by main_form's owner-draw and
  // rendered with a yellow background + bold black text. Variant by which
  // shortcuts were created so the user knows exactly where to click.
  if madeDesktop or madeFolder then begin
    var TgtDir := IncludeTrailingPathDelimiter(FCfg.TargetDir);
    Log('');
    Log('============================================================');
    if madeDesktop and madeFolder then begin
      Log('IMPORTANT: start the IDE from the desktop shortcut');
      Log('IMPORTANT: "' + Name + '", or the copy inside the');
      Log('IMPORTANT: install folder ' + TgtDir + '.');
    end else if madeDesktop then begin
      Log('IMPORTANT: start the IDE from the desktop shortcut');
      Log('IMPORTANT: "' + Name + '".');
    end else begin
      Log('IMPORTANT: start the IDE from the shortcut inside the');
      Log('IMPORTANT: install folder ' + TgtDir + '.');
    end;
    Log('IMPORTANT: The raw lazarus binary skips --pcp and breaks');
    Log('IMPORTANT: the docked layout -- always use the shortcut.');
    Log('============================================================');
  end;
  Result := True;
end;

function TInstallThread.StepGenerateFpcCfg: Boolean;
begin
  Result := False;
  // fpcmkcfg lives in <prefix>/bin/<host-target>/ on Windows and in
  // <prefix>/bin/ on Linux (standard unix prefix layout).
  var FpcMkCfg := HostFpcUtilDir + 'fpcmkcfg' + ExeExt;
  // fpc.cfg sits next to the compiler binary on both OSes so FPC's
  // config search order finds it without needing /etc/fpc.cfg or
  // ~/.fpc.cfg fallbacks.
  var CfgPath  := HostFpcBinDir + 'fpc.cfg';
  // fpcmkcfg template uses %basepath%/units/$fpctarget for unit search
  // paths. The right basepath depends on the install layout:
  //   Windows: <install>/fpc/{units,bin}/<target>/  -- basepath=<install>/fpc
  //   Linux:   <install>/fpc/lib/fpc/<ver>/units/<target>/  -- basepath=
  //                <install>/fpc/lib/fpc/<ver>
  // Using <install>/fpc on Linux makes the template resolve to
  // <install>/fpc/units/<target>/ which does not exist -> "Can't find
  // unit system" at first Lazarus compile.
{$ifdef WINDOWS}
  var BasePath := IncludeTrailingPathDelimiter(FCfg.TargetDir) + 'fpc';
{$endif}
{$ifdef LINUX}
  var BasePath := ExcludeTrailingPathDelimiter(HostFpcBinDir);
{$endif}

  // make install does not generate fpc.cfg (the official Inno Setup
  // installer does it as a [Run] post-install step). Without fpc.cfg
  // the compiler can not find unit search paths beyond rtl, breaking
  // every non-trivial build (e.g. lazarus -> "Can't find unit db").
  // template uses %basepath% to resolve -Fu/-Fl/-FD paths.
  Log('Generating fpc.cfg');
  Log('  fpcmkcfg: ' + FpcMkCfg);
  Log('  output:   ' + CfgPath);
  Log('  basepath: ' + BasePath);
  Progress(-1, 'Generating fpc.cfg');
  if not FileExists(FpcMkCfg) then begin
    FErrorMsg := 'fpcmkcfg binary not found at ' + FpcMkCfg +
                 ' (make install did not place it -- check `make utils_install`)';
    Log('  ' + FErrorMsg);
    Exit;
  end;
  // Defensive: lib/fpc/<ver>/ should exist after rtl_install but
  // double-check so fpcmkcfg's -o doesn't fail on a missing parent.
  ForceDirectories(HostFpcBinDir);
  // RunStream captures fpcmkcfg's stderr (lines) through OnMakeLine so
  // a non-zero exit surfaces the real reason ("Could not open template
  // file ...", "Could not create output file ..." etc.) in the UI log
  // instead of just "exit=1".
  var ExitCode := RunStream(FpcMkCfg, ['-d', 'basepath=' + BasePath, '-o', CfgPath, '-s'], '', '', @OnMakeLine);
  if ExitCode <> 0 then begin
    FErrorMsg := 'fpcmkcfg failed (exit=' + IntToStr(ExitCode) + ')';
    Log('  ' + FErrorMsg);
    Exit;
  end;
  Log('fpc.cfg ready: ' + CfgPath);
{$ifdef LINUX}
  // fpcmkcfg's default template uses -FD%basepath%/bin/$FPCTARGET for
  // tool lookup (fpcres, fpcsubst, ...). That layout is what Windows
  // has -- bin/<target>/. On Linux the unix prefix convention puts
  // utilities flat in <prefix>/bin/, so the default -FD resolves to a
  // non-existent dir and Lazarus compiles fail with "Resource
  // compiler fpcres not found". Append a working -FD that points at
  // the real utility dir; FPC scans all -FD entries until it finds
  // the requested utility, so leaving the broken one in place is
  // harmless and saves us a search-and-replace.
  try
    var CfgSl := autofree TStringList.Create;
    CfgSl.LoadFromFile(CfgPath);
    CfgSl.Add('');
    CfgSl.Add('# Linux: utilities (fpcres etc.) live in <prefix>/bin/, not in');
    CfgSl.Add('# <prefix>/lib/fpc/<ver>/bin/$FPCTARGET as the default template assumes');
    CfgSl.Add('-FD' + ExcludeTrailingPathDelimiter(HostFpcUtilDir));
    CfgSl.SaveToFile(CfgPath);
    Log('  appended -FD ' + ExcludeTrailingPathDelimiter(HostFpcUtilDir));
  except
    on E: Exception do
      Log('  WARN: could not append -FD to fpc.cfg: ' + E.Message);
  end;
{$endif}
  // FPC's config-file search prefers a user-level fpc.cfg over the one next
  // to the compiler (~/.fpc.cfg on Linux, %USERPROFILE%\fpc.cfg and
  // %ALLUSERSPROFILE%\fpc.cfg on Windows) - compiler-relative is the
  // last-resort fallback, not the first hit. A user with any prior FPC
  // experiment leaves one behind, and its stale -Fu paths win over the
  // portable fpc.cfg we just generated -> foreign .ppu files pulled into
  // the build ("Can't find unit system", or a generic that fails to
  // specialize because its recorded token stream is from another compiler).
  // Override the search by pointing PPC_CONFIG_PATH at our cfg dir;
  // ApplyEnvWithPathPrefix copies it into every child make / lazbuild.
  var ConfigDir := ExcludeTrailingPathDelimiter(HostFpcBinDir);
  fpcConfigDir := ConfigDir;
  Log('  PPC_CONFIG_PATH = ' + ConfigDir);
{$ifdef LINUX}
  c_setenv('PPC_CONFIG_PATH', PChar(ConfigDir), 1);
  // Warn if the user has ~/.fpc.cfg; our pipeline is now safe (overridden
  // via env), but `fpc` invoked manually from a shell after install will
  // still hit it unless the user removes/renames it.
  var DotFpcCfg := IncludeTrailingPathDelimiter(GetEnvironmentVariable('HOME')) + '.fpc.cfg';
  if FileExists(DotFpcCfg) then begin
    Log('  NOTE: ~/.fpc.cfg detected at ' + DotFpcCfg);
    Log('  NOTE: it shadows portable fpc.cfg for plain `fpc` shell use.');
    Log('  NOTE: rename or delete it if you want this install to be the default.');
  end;
{$endif}
{$ifdef WINDOWS}
  // Same warning for the two Windows spots, both searched before the
  // compiler dir.
  for var Shadow in [IncludeTrailingPathDelimiter(GetEnvironmentVariable('USERPROFILE')) + 'fpc.cfg',
                     IncludeTrailingPathDelimiter(GetEnvironmentVariable('ALLUSERSPROFILE')) + 'fpc.cfg'] do
    if FileExists(Shadow) then begin
      Log('  NOTE: user-level fpc.cfg detected at ' + Shadow);
      Log('  NOTE: it shadows portable fpc.cfg for plain `fpc` shell use.');
      Log('  NOTE: rename or delete it if you want this install to be the default.');
    end;
{$endif}
  // Dump the unit-search-path lines so we can visually verify the
  // template resolved %basepath% correctly. -Fu lines that don't
  // resolve to real dirs on disk are how we end up with "Can't find
  // unit system" at first compile.
  try
    var Sl := autofree TStringList.Create;
    Sl.LoadFromFile(CfgPath);
    var n := 0;
    for var i := 0 to Sl.Count - 1 do begin
      var line := Trim(Sl[i]);
      if (Length(line) > 3) and ((Copy(line, 1, 3) = '-Fu') or (Copy(line, 1, 3) = '-Fl') or (Copy(line, 1, 3) = '-FD') or (Copy(line, 1, 3) = '-FE')) then begin
        Log('  cfg: ' + line);
        Inc(n);
        if n >= 12 then Break;
      end;
    end;
  except
  end;
  Result := True;
end;

// Pull the optional add-on packages (FWHexView + CPUView) off the
// components-v1 release into <TargetDir>/components_extra/. We never
// re-download: presence of the unzipped folder is the cache key.
// Failure here is fatal because the caller already decided the user
// wants the add-on -- proceeding without it would silently produce
// an IDE without the requested feature.
function TInstallThread.StepDownloadComponents: Boolean;

  // Download <Url> -> <DestZip>, verify SHA256, extract into <DestDir>.
  // Returns False on any error (caller surfaces FErrorMsg).
  function FetchAndExtract(const Url, Sha, Label_, DestDir: string): Boolean;
  begin
    Result := False;
    var ZipFile := IncludeTrailingPathDelimiter(GetTempDir) +
                   Label_ + '.zip';
    if not DownloadAndVerify(Url, Sha, ZipFile, Label_) then Exit;
    if DirectoryExists(DestDir) then RemoveDir(DestDir);
    if not ForceDirectories(DestDir) then begin
      FErrorMsg := 'cannot create ' + DestDir;
      Exit;
    end;
    Log('Extracting ' + Label_ + ' to ' + DestDir);
    Progress(-1, 'Extracting ' + Label_);
    if not ExtractZip(ZipFile, DestDir, @Progress) then begin
      FErrorMsg := Label_ + ' extract failed';
      Exit;
    end;
    DeleteFile(ZipFile);
    Result := True;
  end;

begin
  Result := True;
  // Skip the whole stage if none of the optional component-bundle addons
  // are requested -- no need to touch the network at all in that case.
  // ToggleDisplayAffinity only triggers the fetch on Windows hosts (its
  // checkbox is locked off elsewhere), so the guard reflects that.
  var WantAnything := FCfg.InstallCPUView or FCfg.InstallMetaDarkStyle;
{$ifdef WINDOWS}
  WantAnything := WantAnything or FCfg.InstallToggleAffinity;
{$endif}
  if not WantAnything then begin
    Log('No optional components requested; skipping fetch');
    Exit;
  end;

  var Base := ComponentsExtraDir;
  ForceDirectories(Base);

  if FCfg.InstallCPUView then begin
    // FWHexView is a hard dependency of CPUView (CPUView_<plat>_D.lpk's
    // RequiredPkgs lists FWHexView.LCL). Fetch it first.
    var FwhexDir := IncludeTrailingPathDelimiter(Base) + 'FWHexView';
    if not DirectoryExists(IncludeTrailingPathDelimiter(FwhexDir) + 'src') then begin
      Result := FetchAndExtract(COMPONENTS_FWHEX_URL, COMPONENTS_FWHEX_SHA, 'FWHexView 2.0.16', FwhexDir);
      if not Result then Exit;
    end
    else
      Log('FWHexView already present at ' + FwhexDir + ', skipping fetch');

    var CpuDir := IncludeTrailingPathDelimiter(Base) + 'CPUView';
    if not DirectoryExists(IncludeTrailingPathDelimiter(CpuDir) + 'src') then begin
      Result := FetchAndExtract(COMPONENTS_CPUVIEW_URL, COMPONENTS_CPUVIEW_SHA, 'CPUView 1.0', CpuDir);
      if not Result then Exit;
    end
    else
      Log('CPUView already present at ' + CpuDir + ', skipping fetch');
  end;

{$ifdef WINDOWS}
  if FCfg.InstallToggleAffinity then begin
    // Zip extracts flat (LICENSE / README.md / .lpk / .pas at root) into
    // <Base>/ToggleDisplayAffinity/. Presence-cache key is the .lpk file
    // itself because the zip has no src/ subdir to probe.
    var ToggleDir := IncludeTrailingPathDelimiter(Base) + 'ToggleDisplayAffinity';
    if not FileExists(IncludeTrailingPathDelimiter(ToggleDir) +
                      'toggledisplayaffinity.lpk') then begin
      Result := FetchAndExtract(COMPONENTS_TOGGLE_URL, COMPONENTS_TOGGLE_SHA, 'ToggleDisplayAffinity 1.0', ToggleDir);
      if not Result then Exit;
    end
    else
      Log('ToggleDisplayAffinity already present at ' + ToggleDir + ', skipping fetch');
  end;
{$endif}

  if FCfg.InstallMetaDarkStyle then begin
    // Zip has both .lpk files (runtime + design-time) at root plus a src/
    // tree. Presence-cache key is the design-time .lpk -- both .lpks
    // travel together so checking just one is enough.
    var MetaDir := IncludeTrailingPathDelimiter(Base) + 'MetaDarkStyle';
    if not FileExists(IncludeTrailingPathDelimiter(MetaDir) +
                      'metadarkstyledsgn.lpk') then begin
      Result := FetchAndExtract(COMPONENTS_METADARK_URL, COMPONENTS_METADARK_SHA, 'MetaDarkStyle 0.9', MetaDir);
      if not Result then Exit;
    end
    else
      Log('MetaDarkStyle already present at ' + MetaDir + ', skipping fetch');
  end;
end;

function TInstallThread.StepRemoveCrossWin32: Boolean;
begin
  Result := True;  // best-effort
  var FpcInstall := IncludeTrailingPathDelimiter(FCfg.TargetDir) + 'fpc';
  var PpcrossBin := HostFpcBinDir + 'ppcross386' + ExeExt;
  var UnitsDir   := IncludeTrailingPathDelimiter(FpcInstall) +
                    'units' + DirectorySeparator + 'i386-win32';

  Log('Removing cross compiler i386-win32');
  Progress(-1, 'Removing i386-win32');
  if FileExists(PpcrossBin) then begin
    Log('  ' + PpcrossBin);
    DeleteFile(PpcrossBin);
  end;
  if DirectoryExists(UnitsDir) then begin
    Log('  ' + UnitsDir);
    RemoveDir(UnitsDir);
  end;
  stepStageWin32Binutils(False);
end;

procedure TInstallThread.StepM3Cleanup;
begin
  // crossinstall drops a 32-bit native bin tree alongside the cross bits;
  // we only want the cross compiler in x86_64-win64\, so ditch the 32-bit
  // native bin. Matches the workflow's "Cleanup" step.
  // (fpc322 bootstrap stays - lazarus build still needs make.exe and
  // binutils from there.)
  // i386-win32 cross is only meaningful on a Windows host (Linux host
  // would cross-from-linux which is a different code path entirely).
  var P := IncludeTrailingPathDelimiter(FCfg.TargetDir) +
           'fpc' + DirectorySeparator + 'bin' +
           DirectorySeparator + 'i386-win32';
  if DirectoryExists(P) then begin
    Log('Removing ' + P);
    Progress(-1, 'Cleanup: drop i386-win32 native bin');
    RemoveDir(P);
  end;
end;

procedure TInstallThread.Execute;
var
  Manifest: TInstallManifest;
begin
  FSuccess := False;
  FErrorMsg := '';
  FLogStream := nil;
  FLoggedMakeDiag := False;
  FHostFpcVersion := '';     // re-detect each run; user may have wiped fpc/
  try
    if not (FCfg.InstallFpc or FCfg.InstallLazarus) then begin
      Log('nothing to install');
      FSuccess := True;
      Exit;
    end;

    if not DirectoryExists(FCfg.TargetDir) then
      if not ForceDirectories(FCfg.TargetDir) then begin
        FErrorMsg := 'cannot create directory ' + FCfg.TargetDir;
        Exit;
      end;

    // open installer.log AFTER the target dir exists so the create call
    // never fails on a missing parent. fmCreate truncates each run -
    // each install gets its own clean log, no accumulation.
    if FCfg.SaveLog then
    try
      var LogPath := ResolveLogPath;
      FLogStream := TFileStream.Create(LogPath, fmCreate);
      Log('installer.log: ' + LogPath);
    except
      on E: Exception do begin
        FLogStream := nil;
        // surface, but don't abort - logging is a nice-to-have
        FLogMsg := 'WARNING: could not open installer.log: ' + E.Message;
        Synchronize(@SyncLog);
      end;
    end;

    // pipeline is idempotent: each step checks its end-state and skips
    // if already done. clicking 'Reinstall' on an existing install does
    // not redo a 25-minute build pointlessly; it just applies whatever
    // delta the user requested via checkboxes (typically: add or
    // remove a cross compiler), or - if the user picked a different
    // commit/branch - refreshes only the affected component.
    var TargetPrefix    := IncludeTrailingPathDelimiter(FCfg.TargetDir);
    // Use the same compiler / wrapper / units paths as the rest of the
    // pipeline so detection lines up with what the install steps create.
    var hasFpcExe       := FileExists(HostFpcUtilDir + 'fpc' + ExeExt);
    var hasLazExe       := FileExists(IncludeTrailingPathDelimiter(LazarusDir) + 'lazarus' + ExeExt);
    var hasCrossW32     := FileExists(HostFpcBinDir + 'ppcross386' + ExeExt);
    var hasCrossWasm    := FileExists(HostFpcBinDir + 'ppcrosswasm32' + ExeExt);
    // Linux cross compilers don't get a dedicated ppcross<arch> binary
    // (ppcx64 / ppcross386 are multi-OS), so detect by RTL units presence.
    // x86_64-linux units only signal "cross is installed" on Windows host;
    // on Linux host that dir IS the native target -- ditto for win64.
{$ifdef WINDOWS}
    var hasCrossLinux64 := DirectoryExists(HostFpcUnitsDir + 'x86_64-linux');
    var hasCrossWin64   := True;  // n/a: host = win64; cross-to-win64 meaningless
{$endif}
{$ifdef LINUX}
    var hasCrossLinux64 := True;  // n/a: host = linux64
    var hasCrossWin64   := DirectoryExists(HostFpcUnitsDir + 'x86_64-win64');
{$endif}
    var hasCrossLinux32 := DirectoryExists(HostFpcUnitsDir + 'i386-linux');
    var hasBootstrap    := FileExists(IncludeTrailingPathDelimiter(BootstrapBinDir) +
                                      BootstrapPpName + ExeExt);
    logHostFpcEnv;
    Log(Format('current state: fpc=%s laz=%s cross386=%s wasm=%s ' +
               'linux64=%s linux32=%s win64=%s bootstrap=%s', [BoolToStr(hasFpcExe, True), BoolToStr(hasLazExe, True),
       BoolToStr(hasCrossW32, True), BoolToStr(hasCrossWasm, True), BoolToStr(hasCrossLinux64, True), BoolToStr(hasCrossLinux32, True),
       BoolToStr(hasCrossWin64, True), BoolToStr(hasBootstrap, True)]));

    // i386-linux needs ppcross386 (the same i386 codegen binary serves
    // both -Twin32 and -Tlinux at runtime; it's produced by the
    // i386-win32 cross step). If the user requested linux32 without
    // already having ppcross386 AND without ticking i386-win32 in the
    // same run, fail upfront with a clear message rather than running
    // 10 minutes of native build only to crash at stage 1/5 of linux32.
    if FCfg.CrossLinux32 and (not hasCrossW32) and (not FCfg.CrossWin32) then begin
      FErrorMsg := 'i386-linux cross requires the i386-win32 cross compiler. ' +
        'Tick "i386-win32" in the cross list and run install again.';
      Log('ERROR: ' + FErrorMsg);
      Exit;
    end;

    // compare manifest SHAs against what the UI selected; if they
    // differ, force a refresh of just that component.
    Manifest := ReadManifest(FCfg.TargetDir);
    var wantFpcRefresh := False;
    var wantLazRefresh := False;
    if Manifest.Present then begin
      Log(Format('manifest: fpc=%s@%s laz=%s@%s', [Manifest.FpcBranch, Copy(Manifest.FpcSha, 1, 7), Manifest.LazBranch, Copy(Manifest.LazSha, 1, 7)]));
      if hasFpcExe and (FCfg.FpcSelectedSha <> '') and (LowerCase(FCfg.FpcSelectedSha) <> Manifest.FpcSha) then begin
        Log('FPC selection (' + Copy(FCfg.FpcSelectedSha, 1, 7) +
            ') differs from installed (' + Copy(Manifest.FpcSha, 1, 7) +
            ') -> wiping fpcsrc + fpc to force fresh build');
        wantFpcRefresh := True;
      end;
      if hasLazExe and (FCfg.LazSelectedSha <> '') and (LowerCase(FCfg.LazSelectedSha) <> Manifest.LazSha) then begin
        Log('Lazarus selection (' + Copy(FCfg.LazSelectedSha, 1, 7) +
            ') differs from installed (' + Copy(Manifest.LazSha, 1, 7) +
            ') -> wiping lazarus to force fresh build');
        wantLazRefresh := True;
      end;
    end;

    // clean gets its own stage: the trees are huge and their removal runs minutes, so each dir
    // gets an equal slice of the stage bar and removeDirVerbose streams per-subdir log lines
    if wantFpcRefresh or wantLazRefresh then begin
      SetStage(isCleanPrev);
      var CleanDirs := autofree TStringList.Create;
      if wantFpcRefresh then begin
        CleanDirs.Add(TargetPrefix+'fpc');
        CleanDirs.Add(TargetPrefix+'fpcsrc');
        CleanDirs.Add(TargetPrefix+'cross');
      end;
      if wantLazRefresh then CleanDirs.Add(TargetPrefix+'lazarus');
      for var i := 0 to CleanDirs.Count-1 do
        removeDirVerbose(CleanDirs[i], (i*100) div CleanDirs.Count, ((i+1)*100) div CleanDirs.Count);
    end;
    if wantFpcRefresh then begin
      hasFpcExe := False;
      hasCrossW32 := False;
      hasCrossWasm := False;
{$ifdef WINDOWS}
      hasCrossLinux64 := False;
{$endif}
{$ifdef LINUX}
      hasCrossWin64 := False;
{$endif}
      hasCrossLinux32 := False;
    end;
    if wantLazRefresh then hasLazExe := False;

    // bootstrap is needed for any make-based step; only re-fetch if missing
    SetStage(isBootstrap);
    if hasBootstrap then
      Log('bootstrap fpc322 already installed, skipping')
    else
    begin
      // bootstrap is needed for any make-based build below; only run if
      // we will actually need it (FPC build or cross compiler add)
      if (not hasFpcExe) or (FCfg.CrossWin32 and not hasCrossW32) or (FCfg.CrossWasm and not hasCrossWasm) or (FCfg.CrossLinux64 and not hasCrossLinux64) or
         (FCfg.CrossLinux32 and not hasCrossLinux32) or (FCfg.CrossWin64 and not hasCrossWin64) then
        if not StepBootstrap then Exit;
    end;

    // FPC source + native build - skip if FPC binary already there.
    // user must manually wipe <fpc> to force a rebuild.
    if hasFpcExe then
      Log('native FPC already built at <target>\fpc, skipping source + make all')
    else
    begin
      SetStage(isFpcSrc);
      if not StepDownloadFpcSource then Exit;
      if not StepBuildFpcNative then Exit;
    end;

    // fpc.cfg has to exist before any cross step that wants to patch it
    // (Linux cross appends a target-specific section). Pulled ahead of
    // the cross blocks so a brand-new install lands in the right order.
    // Always regenerate: cheap (~50ms) and avoids the "stale fpc.cfg
    // from a previous installer version with wrong basepath" trap.
    SetStage(isFpcCfg);
    if not StepGenerateFpcCfg then Exit;

    // cross i386-win32: smart add/remove based on checkbox + current state.
{$ifdef WINDOWS}
    // native binutils: unconditional, also repairs pre-existing installs
    if not stepStageWin64Binutils then exit;
    if FCfg.CrossWin32 and (not hasCrossW32) then begin
      SetStage(isFpcCross);
      if not StepBuildFpcCross then Exit;
      StepM3Cleanup;
    end
    else if (not FCfg.CrossWin32) and hasCrossW32 then begin
      if not StepRemoveCrossWin32 then Exit;
    end
    else if hasCrossW32 then
      Log('cross compiler i386-win32 already installed, leaving as is')
    else
      Log('skipping cross compiler i386-win32 (not selected)');
    // unconditional on every run with win32 ticked; installs made before
    // this step exist without the binutils and get repaired here
    if FCfg.CrossWin32 then if not stepStageWin32Binutils(True) then exit;
{$endif}
{$ifdef LINUX}
    // Linux host -> i386-win32: same staged pattern as cross-win64-from-linux,
    // internal -Xi linker for PE/COFF; produces ppcross386 reused below by
    // cross-i386-linux if the user also picked that.
    if FCfg.CrossWin32 and (not hasCrossW32) then begin
      SetStage(isFpcCross);
      if not StepBuildFpcCrossWin32FromLinux then Exit;
    end
    else if (not FCfg.CrossWin32) and hasCrossW32 then begin
      if not StepRemoveCrossWin32FromLinux then Exit;
    end
    else if hasCrossW32 then
      Log('cross compiler i386-win32 already installed, leaving as is')
    else
      Log('skipping cross compiler i386-win32 (not selected)');
{$endif}

    // cross wasm32-wasip1: same smart add/remove pattern. WASM has no
    // external binutils / libc, so the build is just compiler + RTL units.
    if FCfg.CrossWasm and (not hasCrossWasm) then begin
      SetStage(isFpcCrossWasm);
      if not StepBuildFpcCrossWasm then Exit;
    end
    else if (not FCfg.CrossWasm) and hasCrossWasm then begin
      if not StepRemoveCrossWasm then Exit;
    end
    else if hasCrossWasm then
      Log('cross compiler wasm32-wasip1 already installed, leaving as is')
    else
      Log('skipping cross compiler wasm32-wasip1 (not selected)');
    // repairs installs made before the cfg block existed
    if FCfg.CrossWasm then PatchFpcCfgCrossSection('wasip1', 'wasm32', ExcludeTrailingPathDelimiter(HostFpcBinDir), '', '', True);

{$ifdef LINUX}
    // cross x86_64-win64 from a linux host: uses FPC's internal PE/COFF
    // linker (-Xi), so no external mingw-w64 binutils / Win64 import libs
    // to ship. Same idempotent add/remove pattern as the other crosses.
    if FCfg.CrossWin64 and (not hasCrossWin64) then begin
      SetStage(isFpcCrossLinux64);   // reuse slot for cross stage progress
      if not StepBuildFpcCrossWin64FromLinux then Exit;
    end
    else if (not FCfg.CrossWin64) and hasCrossWin64 then begin
      if not StepRemoveCrossWin64FromLinux then Exit;
    end
    else if hasCrossWin64 then
      Log('cross compiler x86_64-win64 already installed, leaving as is')
    else
      Log('skipping cross compiler x86_64-win64 (not selected)');
{$endif}

    // cross x86_64-linux: download zips + verify SHA + extract + crossinstall
    // + patch fpc.cfg with target section. Same smart add/remove pattern.
    // already-installed branch re-runs the fpc.cfg patcher so config tweaks
    // shipped with newer installer versions reach pre-existing installs
    // without forcing a full rebuild of the cross. On Linux host this is
    // native, not a cross -- guard the whole block.
{$ifdef WINDOWS}
    if FCfg.CrossLinux64 and (not hasCrossLinux64) then begin
      SetStage(isFpcCrossLinux64);
      if not StepBuildFpcCrossLinux64 then Exit;
    end
    else if (not FCfg.CrossLinux64) and hasCrossLinux64 then begin
      if not StepRemoveCrossLinux64 then Exit;
    end
    else if hasCrossLinux64 then begin
      Log('cross compiler x86_64-linux already installed, refreshing fpc.cfg block');
      var BinDir := TargetPrefix + 'cross' + DirectorySeparator + 'x86_64-linux' +
                    DirectorySeparator + 'bin';
      var LibDir := TargetPrefix + 'cross' + DirectorySeparator + 'x86_64-linux' +
                    DirectorySeparator + 'lib';
      PatchFpcCfgCrossSection('linux', 'x86_64', BinDir, LibDir, 'x86_64-linux-gnu-', True);
    end
    else
      Log('skipping cross compiler x86_64-linux (not selected)');
{$endif}

    // cross i386-linux: requires ppcross386 from the i386-win32 step
    // (same multi-target binary serves both -Twin32 and -Tlinux).
{$ifdef WINDOWS}
    if FCfg.CrossLinux32 and (not hasCrossLinux32) then begin
      SetStage(isFpcCrossLinux32);
      if not StepBuildFpcCrossLinux32 then Exit;
    end
    else if (not FCfg.CrossLinux32) and hasCrossLinux32 then begin
      if not StepRemoveCrossLinux32 then Exit;
    end
    else if hasCrossLinux32 then begin
      Log('cross compiler i386-linux already installed, refreshing fpc.cfg block');
      var BinDir := TargetPrefix + 'cross' + DirectorySeparator + 'i386-linux' +
                    DirectorySeparator + 'bin';
      var LibDir := TargetPrefix + 'cross' + DirectorySeparator + 'i386-linux' +
                    DirectorySeparator + 'lib';
      PatchFpcCfgCrossSection('linux', 'i386', BinDir, LibDir, 'i386-linux-gnu-', True);
    end
    else
      Log('skipping cross compiler i386-linux (not selected)');
{$endif}
{$ifdef LINUX}
    // Linux host -> i386-linux: requires ppcross386 (built either here in
    // the i386-win32 step that just ran, or already present from a prior
    // run). Internal -Xi for ELF generation; no external i386 binutils
    // bundle needed.
    if FCfg.CrossLinux32 and (not hasCrossLinux32) then begin
      SetStage(isFpcCrossLinux32);
      if not StepBuildFpcCrossLinux32FromLinux then Exit;
    end
    else if (not FCfg.CrossLinux32) and hasCrossLinux32 then begin
      if not StepRemoveCrossLinux32FromLinux then Exit;
    end
    else if hasCrossLinux32 then
      Log('cross compiler i386-linux already installed, leaving as is')
    else
      Log('skipping cross compiler i386-linux (not selected)');
{$endif}

    if FCfg.InstallLazarus and (not hasLazExe) then begin
      SetStage(isLazSrc);
      if not StepDownloadLazarusSource then Exit;
      // download CPU-View / FWHexView before lazbuild --add-package runs
      // so the package-registration loop in StepBuildLazarus finds the
      // .lpk files on disk. Stage progress moves between make-lazbuild
      // and package registration.
      SetStage(isLazComponents);
      if not StepDownloadComponents then Exit;
      if not StepBuildLazarus then Exit;
      SetStage(isLazConfig);
      if not StepGenerateLazarusConfig then Exit;
      runHelpSteps;
      SetStage(isShortcut);
      if not StepCreateShortcuts then Exit;
    end
    else if hasLazExe and FCfg.InstallLazarus then begin
      // Lazarus is already built. Check whether the user changed any
      // addon selection vs what the manifest recorded last time -- if
      // so, run a smaller "add packages + rebuild IDE" step instead of
      // a full reinstall.
      var addonsChanged := (FCfg.InstallMinimap <> Manifest.InstallMinimap) or (FCfg.InstallUnleashedMinimap <> Manifest.InstallUnleashedMinimap) or (FCfg.InstallCPUView <> Manifest.InstallCPUView) or (FCfg.InstallMetaDarkStyle <> Manifest.InstallMetaDarkStyle)
{$ifdef WINDOWS}
                           or (FCfg.InstallToggleAffinity <> Manifest.InstallToggleAffinity)
{$endif}
                           ;
      if addonsChanged then begin
        Log('lazarus already built but addon selection changed -- rebuilding IDE');
        if not StepRebuildLazarusForAddons then Exit;
      end
      else
        Log('lazarus already built at <target>\lazarus, no addon delta, skipping');
      // update run: no shortcut step here, so help closes the log
      runHelpSteps;
    end
    else
      Log('skipping Lazarus IDE (not selected)');

    // record what's now on disk so a later run can compare
    Manifest.Present     := True;
    Manifest.FpcBranch   := FCfg.FpcBranch;
    Manifest.FpcSha      := FCfg.FpcSelectedSha;
    Manifest.FpcLatest   := FCfg.FpcLatest;
    Manifest.LazBranch   := FCfg.LazBranch;
    Manifest.LazSha      := FCfg.LazSelectedSha;
    Manifest.LazLatest   := FCfg.LazLatest;
    // Cross-target detection by RTL units presence (the multi-target
    // ppcrossx64 / ppcross386 binaries are reused, so units dir is the
    // signal). On Windows host x86_64-win64 is native (always present)
    // and CrossWin64 is meaningless -> record user's intent. On Linux
    // host x86_64-linux is native -> CrossLinux64 mirrors intent.
{$ifdef WINDOWS}
    Manifest.CrossWin64   := FCfg.CrossWin64;
    Manifest.CrossLinux64 := DirectoryExists(HostFpcUnitsDir + 'x86_64-linux');
{$endif}
{$ifdef LINUX}
    Manifest.CrossWin64   := DirectoryExists(HostFpcUnitsDir + 'x86_64-win64');
    Manifest.CrossLinux64 := FCfg.CrossLinux64;
{$endif}
    Manifest.CrossWin32   := FileExists(HostFpcBinDir + 'ppcross386' + ExeExt);
    Manifest.CrossLinux32 := DirectoryExists(HostFpcUnitsDir + 'i386-linux');
    Manifest.CrossWasm    := FileExists(HostFpcBinDir + 'ppcrosswasm32' + ExeExt);
    Manifest.InstallMinimap := FCfg.InstallMinimap;
    Manifest.InstallUnleashedMinimap := FCfg.InstallUnleashedMinimap;
    Manifest.InstallCPUView := FCfg.InstallCPUView;
    Manifest.InstallMetaDarkStyle := FCfg.InstallMetaDarkStyle;
    // record what actually landed on disk, not what was ticked -- a failed
    // download must leave the next run willing to retry
    Manifest.InstallHelpFiles := FileExists(IncludeTrailingPathDelimiter(LazarusDir)+'docs'+DirectorySeparator+'chm'+DirectorySeparator+'rtl.chm');
    // ToggleDisplayAffinity is Windows-only. On Linux, FCfg's value is
    // always False (UI checkbox locked off), so writing it here would
    // erase a flag a previous Windows install set. Preserve whatever
    // ReadManifest returned on non-Windows hosts.
{$ifdef WINDOWS}
    Manifest.InstallToggleAffinity := FCfg.InstallToggleAffinity;
{$endif}
    Manifest.LaunchAfter := FCfg.LaunchAfter;
    Manifest.MakeDesktopShortcut := FCfg.MakeDesktopShortcut;
    Manifest.MakeFolderShortcut  := FCfg.MakeFolderShortcut;
    Manifest.InstalledAt := FormatDateTime('yyyy-mm-dd"T"hh:nn:ss', Now);
    // canonical absolute path; ExpandFileName resolves relative cwd-based input + normalises separators
    Manifest.InstallPath := ExpandFileName(FCfg.TargetDir);
    if WriteManifest(FCfg.TargetDir, Manifest) then
      Log('Manifest written: ' + ManifestPathFor(FCfg.TargetDir))
    else
      Log('WARNING: could not write manifest at ' + ManifestPathFor(FCfg.TargetDir));

    SetStage(isDone);
    Log('--- pipeline done ---');
    Progress(100, 'complete');
    FSuccess := True;
  except
    on E: Exception do
      FErrorMsg := E.ClassName + ': ' + E.Message;
  end;
  // make sure installer.log gets flushed + released regardless of success
  if FLogStream <> nil then begin
    FLogStream.Free;
    FLogStream := nil;
  end;
end;

end.
