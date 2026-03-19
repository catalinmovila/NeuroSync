%% 
function FP_TTL_USV_MasterApp
% FP_TTL_USV_MasterApp
% --------------------
% This is the main "controller" UI for the whole project.
%
% Big picture:
%   - SETUP tab: user selects input files for MAIN and SECONDARY experiments.
%   - Four pipeline buttons (per experiment):
%       1) FP correction            -> *_CorrectedSignal.mat
%       2) TTL sync mapping         -> *_SYNC_MAPPING.xlsx
%       3) Apply mapping to USV     -> *_SHIFTED.mat
%       4) Export overview Excel    -> *_experiment_overview.xlsx
%   - Viewer tabs embed other apps (TimeOfEvents / Browser / Compare / USV Summary).
%
% Where state is stored:
%   - fig.UserData is a struct called UD (UserData).
%   - UD.S.main and UD.S.cmp store all paths + outputs for each experiment.
%   - UD.modules.* store handles to embedded viewer apps (so we can clear/rebuild).
%   - UD.ui.* store handles to UI controls (edit fields, buttons, labels, etc.).
%
% Important rule (your rule):
%   - Output folder is created next to the FIRST selected input (anchorPath).
%     The folder name is exactly: "Output files".

% FP_TTL_USV_MasterApp (STUDENT STYLE)
% -------------------------------------------------------------------------
% Goal:
%   Same functionality, but written like a beginner student:
%     - explicit variables
%     - simple loops
%     - simple callbacks (buttons store info in Button.UserData)
%     - clear if/else logic
%
% Output folder rule:
%   The FIRST "input" you select (photometry / TTLBox / WAV / USV) becomes
%   the anchor. Output folder is created next to that anchor:
%       <anchor folder>\Output files
%
% Required on MATLAB path:
%   - step1_fp_correction.m
%   - step2_ttl_sync_mapping.m
%   - step3_apply_usv_shift.m
%   - step4_export_overview.m
%   - fp_ttl_usv_default_outdir.m
%
% Embedded viewer apps:
%   - TimesOfEventsV3.m
%   - FP_TTL_USV_Browser_app.m
%   - FP_TTL_USV_compare_app.m
%   - USV_summary_dashboard.m
% -------------------------------------------------------------------------

%% 1) Put project on path
appDir = fileparts(mfilename('fullpath'));
if isempty(appDir)
    appDir = pwd;
end

rootDir = fileparts(appDir);
if isempty(rootDir)
    rootDir = appDir;
end

addpath(genpath(rootDir));

%% 2) Colors (UI polish: expanded palette + font choices)
col = getColors();

%% 3) Main figure + tabs
fig = uifigure('Name','FP / TTL / USV Master App (Student style)', ...
    'Position',[80 60 1550 920], 'Color', col.Figure);

% UI polish (font + a slightly cleaner look)
try
    fig.FontName = col.FontName;
    fig.FontSize = col.FontSize;
catch
end

try
    fig.WindowState = 'maximized';
catch
end

tg = uitabgroup(fig,'Position',[10 10 fig.Position(3)-20 fig.Position(4)-20]);

tabSetup   = uitab(tg,'Title','Setup');
tabTOE     = uitab(tg,'Title','TimeOfEvents');
tabBrowser = uitab(tg,'Title','FP Browser');
tabCompare = uitab(tg,'Title','FP Compare');
tabUSV     = uitab(tg,'Title','USV Summary');
tabLog     = uitab(tg,'Title','Log');

%% 4) State stored in fig.UserData
UD = struct();
% UD will be the single source of truth for the whole app.
% We keep it in fig.UserData so every callback can read/write it.
%
% UD.col      : colors used by UI
% UD.S.main   : state (paths + outputs) for MAIN experiment
% UD.S.cmp    : state (paths + outputs) for SECONDARY experiment
% UD.modules  : handles to embedded viewer apps (so we can clear them)
% UD.ui       : handles to UI widgets (edit fields, labels, table, ...)

UD.col = col;

UD.S = struct();
UD.S.main = initExpState();
UD.S.cmp  = initExpState();

UD.modules = struct();
UD.modules.toe     = [];
UD.modules.browser = [];
UD.modules.compare = [];
UD.modules.usv     = [];

UD.ui = struct();

% Store early (so builders can read colors safely)
fig.UserData = UD;

%% 5) Build SETUP UI (two experiment panels + summary)
setupGrid = uigridlayout(tabSetup,[2 2]);
setupGrid.ColumnWidth = {'1x','1x'};
setupGrid.RowHeight   = {'fit','1x'};
setupGrid.Padding     = [12 12 12 12];
setupGrid.RowSpacing  = 12;
setupGrid.ColumnSpacing = 16;

UD = fig.UserData;

UD.ui.main = buildExperimentPanel(setupGrid, 'MAIN experiment', 'main', fig, col);
UD.ui.main.panel.Layout.Row = 1;
UD.ui.main.panel.Layout.Column = 1;

UD.ui.cmp  = buildExperimentPanel(setupGrid, 'SECONDARY experiment', 'cmp', fig, col);
UD.ui.cmp.panel.Layout.Row = 1;
UD.ui.cmp.panel.Layout.Column = 2;

UD.ui.summary = buildSetupSummaryPanel(setupGrid, fig, col);
UD.ui.summary.panel.Layout.Row = 2;
UD.ui.summary.panel.Layout.Column = 1;
try
    UD.ui.summary.panel.Layout.ColumnSpan = 2;
catch
    try
        UD.ui.summary.panel.Layout.Column = [1 2];
    catch
    end
end

%% 6) Build viewer host tabs
UD.ui.toe     = buildHostTab(tabTOE,     'Build / Refresh TimeOfEvents (MAIN)',                    fig, 'toe', col);
UD.ui.browser = buildHostTab(tabBrowser, 'Build / Refresh Browser (MAIN)',                        fig, 'browser', col);
UD.ui.compare = buildHostTab(tabCompare, 'Build / Refresh Compare (MAIN vs SECONDARY)',           fig, 'compare', col);
UD.ui.usv     = buildHostTab(tabUSV,     'Build / Refresh USV Summary (MAIN vs SECONDARY)',       fig, 'usv', col);

%% 7) Log tab
logGrid = uigridlayout(tabLog,[1 1]);
logGrid.Padding = [12 12 12 12];

UD.ui.logArea = uitextarea(logGrid,'Editable','off');
try
    UD.ui.logArea.FontName = col.MonoFontName;
    UD.ui.logArea.FontSize = col.FontSize;
    UD.ui.logArea.BackgroundColor = col.Field;
    if isprop(UD.ui.logArea,'FontColor')
        UD.ui.logArea.FontColor = col.Text;
    end
catch
end

UD.ui.logArea.Value = {sprintf('Ready. BaseDir: %s', rootDir)};

%% 8) Save UI + state
fig.UserData = UD;

appendLog(fig,'1) Select files in Setup.');
appendLog(fig,'2) Run pipeline buttons per experiment (FP -> TTL sync -> USV shift -> Overview / Event-locked / Reward exports).');
appendLog(fig,'3) Use tabs and click Build/Refresh to embed viewers.');
refreshUI(fig);

end

%% ========================== UI BUILDERS ==========================

function ui = buildExperimentPanel(parent, titleText, which, fig, col)

ui = struct();

ui.panel = uipanel(parent,'Title',titleText);
try
    ui.panel.FontWeight = 'bold';
    ui.panel.BackgroundColor = col.Panel;
    if isprop(ui.panel,'ForegroundColor')
        ui.panel.ForegroundColor = col.Text;
    end
catch
end

g = uigridlayout(ui.panel,[13 3]);
g.RowHeight = {28,28,28,28,28,28,28,28,44,34,34,30,'1x'};
g.ColumnWidth = {170,'1x',110};
g.Padding = [12 12 12 12];
g.RowSpacing = 8;
g.ColumnSpacing = 10;

% Rows we want: label + editfield + browse button
rowInfo = {
    1, 'Raw photometry CSV',  'photo',      'efPhoto'
    2, 'TTLBox CSV',          'ttl',        'efTTL'
    3, 'TTL WAV',             'wav',        'efWav'
    4, 'USV detection MAT',   'usv',        'efUSV'
    5, 'Output folder',       'outdir',     'efOutDir'
    6, 'Corrected FP MAT',    'fpMat',      'efFPmat'
    7, 'Sync mapping XLSX',   'sync',       'efSync'
    8, 'Shifted USV MAT',     'usvShifted', 'efUSVsh'
    };

for i = 1:size(rowInfo,1)
    r        = rowInfo{i,1};
    labelTxt = rowInfo{i,2};
    kind     = rowInfo{i,3};
    efName   = rowInfo{i,4};

    % label
    lbl = uilabel(g,'Text',labelTxt,'HorizontalAlignment','right','FontWeight','bold');
    try
        lbl.Layout.Row = r;
        lbl.Layout.Column = 1;
        if isprop(lbl,'FontColor'), lbl.FontColor = col.Text; end
    catch
    end

    % edit field
    ef = uieditfield(g,'text','Editable','off');
    ef.Layout.Row = r;
    ef.Layout.Column = 2;
    ui.(efName) = ef;

    % UI polish: fields look nicer
    try
        ef.BackgroundColor = col.Field;
        if isprop(ef,'FontName'), ef.FontName = col.FontName; end
        if isprop(ef,'FontSize'), ef.FontSize = col.FontSize; end
    catch
    end

    % browse button
    btn = uibutton(g,'Text','Browse','FontWeight','bold');
    btn.Layout.Row = r;
    btn.Layout.Column = 3;

    % UI polish: browse buttons darker
    try
        btn.BackgroundColor = col.BtnBrowseBG;
        if isprop(btn,'FontColor'), btn.FontColor = col.BtnBrowseFG; end
        if isprop(btn,'FontName'), btn.FontName = col.FontName; end
        if isprop(btn,'FontSize'), btn.FontSize = col.FontSize; end
    catch
    end

    btn.UserData = struct();
    btn.UserData.fig   = fig;
    btn.UserData.which = which;
    btn.UserData.kind  = kind;
    btn.ButtonPushedFcn = @onBrowseButton;

    % store button (optional, helpful for debugging)
    ui.(['btn_' kind]) = btn;
end

% Pipeline buttons row (4 buttons)
btnRow = uigridlayout(g,[1 4]);
btnRow.Layout.Row = 9;
btnRow.Layout.Column = 1;
try
    btnRow.Layout.ColumnSpan = 3;
catch
    try, btnRow.Layout.Column = [1 3]; catch, end
end

btnRow.ColumnWidth = {'1x','1x','1x','1x'};
btnRow.RowHeight = {36};
btnRow.ColumnSpacing = 10;
btnRow.Padding = [0 0 0 0];

ui.btnRunFP    = makeStepButton(btnRow,'Run FP correction',      fig, which, 'fp', col);
ui.btnRunSync  = makeStepButton(btnRow,'Compute TTL sync',       fig, which, 'sync', col);
ui.btnRunShift = makeStepButton(btnRow,'Apply sync to USV',      fig, which, 'shift', col);
ui.btnRunOver  = makeStepButton(btnRow,'Export overview Excel',  fig, which, 'overview', col);

% Extra export row (event-locked / per-second Excel)
btnRow2 = uigridlayout(g,[1 1]);
btnRow2.Layout.Row = 10;
btnRow2.Layout.Column = 1;
try
    btnRow2.Layout.ColumnSpan = 3;
catch
    try, btnRow2.Layout.Column = [1 3]; catch, end
end

btnRow2.ColumnWidth = {'1x'};
btnRow2.RowHeight = {34};
btnRow2.ColumnSpacing = 0;
btnRow2.Padding = [0 0 0 0];

ui.btnRunEventLocked = makeStepButton(btnRow2,'Export event-locked Excel', fig, which, 'eventlocked', col);

% Reward-centered export row (food/drug event tables for article stats)
btnRow3 = uigridlayout(g,[1 2]);
btnRow3.Layout.Row = 11;
btnRow3.Layout.Column = 1;
try
    btnRow3.Layout.ColumnSpan = 3;
catch
    try, btnRow3.Layout.Column = [1 3]; catch, end
end

btnRow3.ColumnWidth = {'1x','1x'};
btnRow3.RowHeight = {34};
btnRow3.ColumnSpacing = 10;
btnRow3.Padding = [0 0 0 0];

ui.btnRunRewardMetrics = makeStepButton(btnRow3,'Export reward-event metrics', fig, which, 'rewardmetrics', col);
ui.btnRunRewardBins    = makeStepButton(btnRow3,'Export reward-bin table',   fig, which, 'rewardbins', col);

% Status + Clear
ui.lblStatus = uilabel(g,'Text','- | USV calls: -', 'FontWeight','bold','FontSize',12);
ui.lblStatus.Layout.Row = 12;
ui.lblStatus.Layout.Column = 1;
try
    ui.lblStatus.Layout.ColumnSpan = 2;
catch
    try, ui.lblStatus.Layout.Column = [1 2]; catch, end
end
ui.lblStatus.HorizontalAlignment = 'left';
try
    if isprop(ui.lblStatus,'FontColor'), ui.lblStatus.FontColor = col.Text; end
    if isprop(ui.lblStatus,'FontName'),  ui.lblStatus.FontName  = col.FontName; end
catch
end

ui.btnClear = uibutton(g,'Text','Clear','FontWeight','bold');
ui.btnClear.Layout.Row = 12;
ui.btnClear.Layout.Column = 3;

% UI polish: clear is red
try
    ui.btnClear.BackgroundColor = col.BtnDangerBG;
    if isprop(ui.btnClear,'FontColor'), ui.btnClear.FontColor = col.BtnDangerFG; end
    if isprop(ui.btnClear,'FontName'), ui.btnClear.FontName = col.FontName; end
    if isprop(ui.btnClear,'FontSize'), ui.btnClear.FontSize = col.FontSize; end
catch
end

ui.btnClear.UserData = struct('fig',fig,'which',which);
ui.btnClear.ButtonPushedFcn = @onClearExperimentButton;

end

function btn = makeStepButton(parent, txt, fig, which, stepName, col)
btn = uibutton(parent,'Text',txt,'FontWeight','bold');
btn.UserData = struct();
btn.UserData.fig   = fig;
btn.UserData.which = which;
btn.UserData.step  = stepName;
btn.ButtonPushedFcn = @onRunStepButton;

% UI polish: pipeline buttons are "primary"
try
    btn.BackgroundColor = col.BtnPrimaryBG;
    if isprop(btn,'FontColor'), btn.FontColor = col.BtnPrimaryFG; end
    if isprop(btn,'FontName'),  btn.FontName  = col.FontName; end
    if isprop(btn,'FontSize'),  btn.FontSize  = col.FontSize; end
catch
end
end

function ui = buildSetupSummaryPanel(parentGrid, fig, col)

ui = struct();
ui.panel = uipanel(parentGrid,'Title','Setup Summary & Quick Actions');
try
    ui.panel.BackgroundColor = col.Panel;
    ui.panel.FontWeight = 'bold';
    if isprop(ui.panel,'ForegroundColor')
        ui.panel.ForegroundColor = col.Text;
    end
catch
end

g = uigridlayout(ui.panel,[1 3]);
g.ColumnWidth = {'2.2x','1.2x','1x'};
g.RowHeight = {'1x'};
g.Padding = [12 12 12 12];
g.ColumnSpacing = 12;

% Summary table
items = {
    'Raw photometry CSV'
    'TTLBox CSV'
    'TTL WAV'
    'USV MAT'
    'Output folder'
    'Corrected FP MAT'
    'Sync mapping XLSX'
    'Shifted USV MAT'
    'Sync mapping (a | b)'
    };

data = [items, repmat({''},numel(items),2)];

ui.tbl = uitable(g,'Data',data,'ColumnName',{'Item','MAIN','SECONDARY'},'ColumnEditable',[false false false]);
ui.tbl.Layout.Column = 1;
try, ui.tbl.RowName = {}; catch, end

% UI polish: zebra table rows
try
    ui.tbl.BackgroundColor = [col.TableRowA; col.TableRowB];
    if isprop(ui.tbl,'FontName'), ui.tbl.FontName = col.FontName; end
    if isprop(ui.tbl,'FontSize'), ui.tbl.FontSize = col.FontSize; end
catch
end

% Notes area
noteText = {
    'Checklist (what needs what)'
    ' '
    'Pipeline per experiment'
    '  1) Run FP correction'
    '     Needs: Raw photometry CSV (+ Output folder)'
    '     Produces: Corrected FP MAT'
    ' '
    '  2) Compute TTL sync'
    '     Needs: TTL WAV + TTLBox CSV (+ Output folder)'
    '     Produces: Sync mapping XLSX (a,b)'
    ' '
    '  3) Apply sync to USV'
    '     Needs: USV MAT + Sync mapping XLSX'
    '     Produces: Shifted USV MAT'
    ' '
    '  4) Export overview Excel'
    '     Needs: Corrected FP MAT + TTLBox CSV + USV MAT (shifted preferred)'
    ' '
    '  5) Export event-locked Excel'
    '     Needs: TTLBox CSV (preferred), Corrected FP MAT for Peaks (optional),'
    '     USV MAT (optional; shifted preferred)'
    ' '
    'Embedded tabs'
    '  - TimeOfEvents (MAIN): raw photometry CSV + TTLBox CSV'
    '  - FP Browser (MAIN): corrected FP MAT (required)'
    '    TTLBox CSV (optional), USV MAT (optional; shifted preferred)'
    '  - FP Compare: corrected FP MAT for MAIN and SECONDARY'
    '  - USV Summary: USV MAT for MAIN and SECONDARY (raw detections)'
    };

ui.notes = uitextarea(g,'Value',noteText,'Editable','off');
ui.notes.Layout.Column = 2;

% UI polish: notes look cleaner
try
    ui.notes.BackgroundColor = col.Field;
    ui.notes.FontName = col.FontName;
    ui.notes.FontSize = col.FontSize;
    if isprop(ui.notes,'FontColor'), ui.notes.FontColor = col.Text; end
catch
end

% Quick actions column
qa = uigridlayout(g,[4 1]);
qa.Layout.Column = 3;
qa.RowHeight = {32,32,32,'1x'};
qa.Padding = [0 0 0 0];
qa.RowSpacing = 10;

ui.btnSwap = uibutton(qa,'Text','Swap MAIN <-> SECONDARY','FontWeight','bold');
ui.btnSwap.Layout.Row = 1;
ui.btnSwap.UserData = struct('fig',fig);
ui.btnSwap.ButtonPushedFcn = @onSwapButton;

% UI polish: swap is warning
try
    ui.btnSwap.BackgroundColor = col.BtnWarnBG;
    if isprop(ui.btnSwap,'FontColor'), ui.btnSwap.FontColor = col.BtnWarnFG; end
    if isprop(ui.btnSwap,'FontName'), ui.btnSwap.FontName = col.FontName; end
    if isprop(ui.btnSwap,'FontSize'), ui.btnSwap.FontSize = col.FontSize; end
catch
end

outRow = uigridlayout(qa,[1 2]);
outRow.Layout.Row = 2;
outRow.ColumnWidth = {'1x','1x'};
outRow.RowHeight = {32};
outRow.ColumnSpacing = 8;
outRow.Padding = [0 0 0 0];

ui.btnOpenMain = uibutton(outRow,'Text','Open Main Output folder');
ui.btnOpenMain.UserData = struct('fig',fig,'which','main');
ui.btnOpenMain.ButtonPushedFcn = @onOpenOutDirButton;

ui.btnOpenComp = uibutton(outRow,'Text','Open Secondary Output folder');
ui.btnOpenComp.UserData = struct('fig',fig,'which','cmp');
ui.btnOpenComp.ButtonPushedFcn = @onOpenOutDirButton;

% UI polish: open buttons are info teal
try
    ui.btnOpenMain.BackgroundColor = col.BtnInfoBG;
    if isprop(ui.btnOpenMain,'FontColor'), ui.btnOpenMain.FontColor = col.BtnInfoFG; end
    ui.btnOpenMain.FontName = col.FontName;
    ui.btnOpenMain.FontSize = col.FontSize;
catch
end

try
    ui.btnOpenComp.BackgroundColor = col.BtnInfoBG;
    if isprop(ui.btnOpenComp,'FontColor'), ui.btnOpenComp.FontColor = col.BtnInfoFG; end
    ui.btnOpenComp.FontName = col.FontName;
    ui.btnOpenComp.FontSize = col.FontSize;
catch
end

ui.btnClearBoth = uibutton(qa,'Text','Clear BOTH','FontWeight','bold');
ui.btnClearBoth.Layout.Row = 3;
ui.btnClearBoth.UserData = struct('fig',fig);
ui.btnClearBoth.ButtonPushedFcn = @onClearBothButton;

try
    ui.btnClearBoth.BackgroundColor = col.BtnDangerBG;
    if isprop(ui.btnClearBoth,'FontColor')
        ui.btnClearBoth.FontColor = col.BtnDangerFG;
    end
    if isprop(ui.btnClearBoth,'FontName'), ui.btnClearBoth.FontName = col.FontName; end
    if isprop(ui.btnClearBoth,'FontSize'), ui.btnClearBoth.FontSize = col.FontSize; end
catch
end

end

function uiTab = buildHostTab(tab, buildText, fig, viewerName, col)

uiTab = struct();

g = uigridlayout(tab,[3 1]);
g.RowHeight = {42,'1x',22};
g.ColumnWidth = {'1x'};
g.Padding = [12 12 12 12];

bar = uigridlayout(g,[1 3]);
bar.Layout.Row = 1;
bar.ColumnWidth = {380,110,'1x'};
bar.Padding = [0 0 0 0];
bar.ColumnSpacing = 10;

btnBuild = uibutton(bar,'Text',buildText);
btnBuild.UserData = struct('fig',fig,'viewer',viewerName);
btnBuild.ButtonPushedFcn = @onBuildViewerButton;

% UI polish: build is primary
try
    btnBuild.BackgroundColor = col.BtnPrimaryBG;
    if isprop(btnBuild,'FontColor'), btnBuild.FontColor = col.BtnPrimaryFG; end
    btnBuild.FontName = col.FontName;
    btnBuild.FontSize = col.FontSize;
catch
end

btnClear = uibutton(bar,'Text','Clear');
btnClear.UserData = struct('fig',fig,'viewer',viewerName);
btnClear.ButtonPushedFcn = @onClearViewerButton;

% UI polish: viewer clear is neutral (not red, because it's not destructive to data)
try
    btnClear.BackgroundColor = col.BtnNeutralBG;
    if isprop(btnClear,'FontColor'), btnClear.FontColor = col.BtnNeutralFG; end
    btnClear.FontName = col.FontName;
    btnClear.FontSize = col.FontSize;
catch
end

uiTab.lbl = uilabel(bar,'Text','', 'FontWeight','bold');
uiTab.lbl.Layout.Column = 3;
uiTab.lbl.HorizontalAlignment = 'left';
try
    if isprop(uiTab.lbl,'FontColor'), uiTab.lbl.FontColor = col.Text; end
    if isprop(uiTab.lbl,'FontName'), uiTab.lbl.FontName = col.FontName; end
    if isprop(uiTab.lbl,'FontSize'), uiTab.lbl.FontSize = col.FontSize; end
catch
end

uiTab.host = uipanel(g,'Title','');
uiTab.host.Layout.Row = 2;
uiTab.host.BorderType = 'line';

% UI polish: host panel background
try
    uiTab.host.BackgroundColor = col.Panel;
catch
end

uiTab.status = uilabel(g,'Text','');
uiTab.status.Layout.Row = 3;
uiTab.status.HorizontalAlignment = 'left';
try
    if isprop(uiTab.status,'FontColor'), uiTab.status.FontColor = col.Text; end
    if isprop(uiTab.status,'FontName'), uiTab.status.FontName = col.FontName; end
    if isprop(uiTab.status,'FontSize'), uiTab.status.FontSize = col.FontSize; end
catch
end

end

%% ========================== BUTTON CALLBACKS ==========================

function onBrowseButton(src, ~)
% Callback for all Browse buttons. Reads which/kind from src.UserData and calls doBrowse().

fig   = src.UserData.fig;
which = src.UserData.which;
kind  = src.UserData.kind;
doBrowse(fig, which, kind);
end

function onRunStepButton(src, ~)
% Callback for all pipeline buttons. Reads which/step from src.UserData and calls doRunStep().

fig   = src.UserData.fig;
which = src.UserData.which;
step  = src.UserData.step;
doRunStep(fig, which, step);
end

function onClearExperimentButton(src, ~)
% Callback: clears one experiment panel (paths + outputs) via doClearExperiment().

fig   = src.UserData.fig;
which = src.UserData.which;
doClearExperiment(fig, which);
end

function onClearBothButton(src, ~)
% Callback: clears both experiments via doClearBoth().

fig = src.UserData.fig;
doClearBoth(fig);
end

function onSwapButton(src, ~)
% Callback: swaps MAIN and SECONDARY state via doSwap().

fig = src.UserData.fig;
doSwap(fig);
end

function onOpenOutDirButton(src, ~)
% Callback: opens the output folder in Windows Explorer (or file browser).

fig   = src.UserData.fig;
which = src.UserData.which;
doOpenOutDir(fig, which);
end

function onBuildViewerButton(src, ~)
% Callback: builds/refreshes the selected viewer tab.

fig    = src.UserData.fig;
viewer = src.UserData.viewer;
doBuildViewer(fig, viewer);
end

function onClearViewerButton(src, ~)
% Callback: clears/unloads the embedded viewer tab.

fig    = src.UserData.fig;
viewer = src.UserData.viewer;
doClearViewer(fig, viewer);
end

%% ========================== MAIN ACTIONS (BEGINNER STYLE) ==========================

function doBrowse(fig, which, kind)
% doBrowse
% --------
% Handles file selection and updates state + UI.
%
% Key points:
%   - Depending on 'kind', we call uigetfile for CSV/WAV/MAT.
%   - The FIRST selection sets exp.anchorPath.
%   - The output folder is created next to exp.anchorPath using fp_ttl_usv_default_outdir().
%   - After selection, we refresh the UI so edit-fields and status update.

UD  = fig.UserData;
exp = UD.S.(which);

selectedPath = '';

try
    if strcmp(kind,'photo')
        [f,p] = uigetfile({'*.csv;*.CSV','Photometry CSV (*.csv)';'*.*','All files'}, ...
            'Select raw photometry CSV');
        if isequal(f,0), return; end
        exp.photoCsv = fullfile(p,f);
        selectedPath = exp.photoCsv;

    elseif strcmp(kind,'ttl')
        [f,p] = uigetfile({'*.csv;*.CSV','TTLBox CSV (*.csv)';'*.*','All files'}, ...
            'Select TTLBox CSV');
        if isequal(f,0), return; end
        exp.ttlCsv = fullfile(p,f);
        selectedPath = exp.ttlCsv;

    elseif strcmp(kind,'wav')
        [f,p] = uigetfile({'*.wav;*.WAV','WAV files (*.wav)';'*.*','All files'}, ...
            'Select TTL WAV');
        if isequal(f,0), return; end
        exp.ttlWav = fullfile(p,f);
        selectedPath = exp.ttlWav;

    elseif strcmp(kind,'usv')
        [f,p] = uigetfile({'*.mat;*.MAT','DeepSqueak MAT (*.mat)';'*.*','All files'}, ...
            'Select USV detection MAT');
        if isequal(f,0), return; end
        exp.usvMat = fullfile(p,f);
        selectedPath = exp.usvMat;

    elseif strcmp(kind,'outdir')
        startDir = suggestedDir(exp);
        d = uigetdir(startDir, 'Select output folder');
        if isequal(d,0), return; end
        exp.outDir = d;
        if isempty(exp.anchorPath)
            exp.anchorPath = d; % manual outdir can also be anchor
        end

    elseif strcmp(kind,'fpMat')
        [f,p] = uigetfile({'*.mat;*.MAT','MAT files (*.mat)';'*.*','All files'}, ...
            'Select corrected FP MAT');
        if isequal(f,0), return; end
        exp.fpMat = fullfile(p,f);

    elseif strcmp(kind,'sync')
        [f,p] = uigetfile({'*.xlsx;*.XLSX','XLSX files (*.xlsx)';'*.*','All files'}, ...
            'Select sync mapping XLSX');
        if isequal(f,0), return; end
        exp.syncXlsx = fullfile(p,f);

    elseif strcmp(kind,'usvShifted')
        [f,p] = uigetfile({'*.mat;*.MAT','MAT files (*.mat)';'*.*','All files'}, ...
            'Select shifted USV MAT');
        if isequal(f,0), return; end
        exp.usvShifted = fullfile(p,f);

    else
        return
    end

    % Apply output-folder rule
    otherOut = '';
    if strcmpi(which,'main')
        otherOut = UD.S.cmp.outDir;
    else
        otherOut = UD.S.main.outDir;
    end

    [exp.outDir, exp.anchorPath] = fp_ttl_usv_default_outdir(exp.outDir, exp.anchorPath, selectedPath, otherOut);

    UD.S.(which) = exp;
    fig.UserData = UD;

    refreshUI(fig);

catch ME
    appendLog(fig, sprintf('[%s][Browse %s] ERROR: %s', expTag(which), kind, ME.message));
end

end

function doRunStep(fig, which, stepName)
% doRunStep
% ---------
% Runs one pipeline step for MAIN or SECONDARY.
%
% Steps:
%   fp       -> step1_fp_correction()
%   sync     -> step2_ttl_sync_mapping()   (produces SYNC_MAPPING.xlsx + mapping a/b)
%   shift    -> step3_apply_usv_shift()    (produces *_SHIFTED.mat)
%   overview -> step4_export_overview()    (produces *_experiment_overview.xlsx)
%
% After running:
%   - We update exp stats (USV call count, last mapping values)
%   - We store exp back into fig.UserData
%   - We refresh the UI

UD  = fig.UserData;
exp = UD.S.(which);

try
    % Ensure output folder exists (even if user did not pick it manually)
    otherOut = '';
    if strcmpi(which,'main')
        otherOut = UD.S.cmp.outDir;
    else
        otherOut = UD.S.main.outDir;
    end
    [exp.outDir, exp.anchorPath] = fp_ttl_usv_default_outdir(exp.outDir, exp.anchorPath, '', otherOut);

    if strcmp(stepName,'fp')
        requireFile(exp.photoCsv,'Raw photometry CSV');
        appendLog(fig, sprintf('[%s] Running FP correction...', expTag(which)));
        exp.fpMat = step1_fp_correction(exp.photoCsv, exp.outDir);

    elseif strcmp(stepName,'sync')
        requireFile(exp.ttlWav,'TTL WAV');
        requireFile(exp.ttlCsv,'TTLBox CSV');
        appendLog(fig, sprintf('[%s] Computing TTL sync mapping...', expTag(which)));

        out = step2_ttl_sync_mapping(exp.ttlWav, exp.ttlCsv, exp.outDir);
        exp.syncXlsx = out.files.SyncXLSX;
        exp.lastMap.a = out.mapping.a;
        exp.lastMap.b = out.mapping.b;

    elseif strcmp(stepName,'shift')
        requireFile(exp.syncXlsx,'Sync mapping XLSX');
        requireFile(exp.usvMat,'USV detection MAT');
        appendLog(fig, sprintf('[%s] Applying mapping to USV times...', expTag(which)));

        [exp.usvShifted, exp.lastMap.a, exp.lastMap.b] = step3_apply_usv_shift(exp.syncXlsx, exp.usvMat, exp.outDir);

    elseif strcmp(stepName,'overview')
        requireFile(exp.fpMat,'Corrected FP MAT');
        requireFile(exp.ttlCsv,'TTLBox CSV');
        requireFile(exp.usvShifted,'USV MAT (SHIFTED/SYNCED)');

        appendLog(fig, sprintf('[%s] Exporting overview Excel...', expTag(which)));
        exp.overviewXlsx = step4_export_overview(exp.fpMat, exp.ttlCsv, exp.usvShifted, exp.outDir, exp.syncXlsx, exp.ttlWav);

    elseif strcmp(stepName,'eventlocked')
        % Prefer shifted USV, but allow raw USV if shifted is not available.
        usvForExport = '';
        if isFileSafe(exp.usvShifted)
            usvForExport = exp.usvShifted;
        elseif isFileSafe(exp.usvMat)
            usvForExport = exp.usvMat;
        end

        if ~isFileSafe(exp.ttlCsv) && ~isFileSafe(exp.fpMat) && ~isFileSafe(usvForExport)
            error('Event-locked export needs at least one valid input (TTLBox CSV, Corrected FP MAT, or USV MAT).');
        end

        appendLog(fig, sprintf('[%s] Exporting event-locked Excel...', expTag(which)));
        exp.eventLockedXlsx = step5_export_event_locked(exp.fpMat, exp.ttlCsv, usvForExport, exp.outDir, exp.syncXlsx);

    elseif strcmp(stepName,'rewardmetrics')
        requireFile(exp.ttlCsv,'TTLBox CSV');

        usvForExport = '';
        if isFileSafe(exp.usvShifted)
            usvForExport = exp.usvShifted;
        elseif isFileSafe(exp.usvMat)
            usvForExport = exp.usvMat;
        end

        appendLog(fig, sprintf('[%s] Exporting reward-event metrics...', expTag(which)));
        exp.rewardMetricsXlsx = step6_export_reward_metrics(exp.fpMat, exp.ttlCsv, usvForExport, exp.outDir, exp.syncXlsx);

    elseif strcmp(stepName,'rewardbins')
        requireFile(exp.ttlCsv,'TTLBox CSV');

        usvForExport = '';
        if isFileSafe(exp.usvShifted)
            usvForExport = exp.usvShifted;
        elseif isFileSafe(exp.usvMat)
            usvForExport = exp.usvMat;
        end

        appendLog(fig, sprintf('[%s] Exporting reward-bin table...', expTag(which)));
        exp.rewardBinsXlsx = step7_export_reward_bins(exp.fpMat, exp.ttlCsv, usvForExport, exp.outDir, exp.syncXlsx);

    else
        return
    end

    exp = updateStats(exp);

    UD.S.(which) = exp;
    fig.UserData = UD;

    refreshUI(fig);

catch ME
    appendLog(fig, sprintf('[%s][Run %s] ERROR: %s', expTag(which), stepName, ME.message));
end

end

function doClearExperiment(fig, which)

UD = fig.UserData;

if strcmpi(which,'main')
    UD.S.main = initExpState();

    % MAIN affects MAIN-only viewers too
    doClearViewer(fig,'toe');
    doClearViewer(fig,'browser');
    doClearViewer(fig,'compare');
    doClearViewer(fig,'usv');

    appendLog(fig,'[MAIN] Cleared selections.');
else
    UD.S.cmp = initExpState();

    % SECONDARY affects compare/usv summary
    doClearViewer(fig,'compare');
    doClearViewer(fig,'usv');

    appendLog(fig,'[SECONDARY] Cleared selections.');
end

fig.UserData = UD;
refreshUI(fig);

end

function doClearBoth(fig)

UD = fig.UserData;

UD.S.main = initExpState();
UD.S.cmp  = initExpState();

doClearViewer(fig,'toe');
doClearViewer(fig,'browser');
doClearViewer(fig,'compare');
doClearViewer(fig,'usv');

fig.UserData = UD;
refreshUI(fig);

appendLog(fig,'[SETUP] Cleared BOTH experiments.');

end

function doSwap(fig)

UD = fig.UserData;

tmp      = UD.S.main;
UD.S.main = UD.S.cmp;
UD.S.cmp  = tmp;

% Clear viewers so old embedded UI does not remain
doClearViewer(fig,'toe');
doClearViewer(fig,'browser');
doClearViewer(fig,'compare');
doClearViewer(fig,'usv');

fig.UserData = UD;
refreshUI(fig);

appendLog(fig,'[SETUP] Swapped MAIN <-> SECONDARY.');

end

function doOpenOutDir(fig, which)

UD  = fig.UserData;
exp = UD.S.(which);

% Ensure output folder exists
otherOut = '';
if strcmpi(which,'main')
    otherOut = UD.S.cmp.outDir;
else
    otherOut = UD.S.main.outDir;
end

[exp.outDir, exp.anchorPath] = fp_ttl_usv_default_outdir(exp.outDir, exp.anchorPath, '', otherOut);

UD.S.(which) = exp;
fig.UserData = UD;
refreshUI(fig);

if isempty(exp.outDir) || ~isFolderSafe(exp.outDir)
    uialert(fig, sprintf('No valid output folder for %s yet.', expTag(which)), 'Open output');
    return
end

try
    openFolder(exp.outDir);
catch ME
    uialert(fig, sprintf('Could not open folder:\n%s\n\n%s', exp.outDir, ME.message), 'Open output');
end

end

function doBuildViewer(fig, whichViewer)

UD = fig.UserData;

try
    if strcmpi(whichViewer,'toe')
        exp = UD.S.main;
        requireFile(exp.ttlCsv,'TTLBox CSV (MAIN)');
        requireFile(exp.photoCsv,'Raw photometry CSV (MAIN)');

        doClearViewer(fig,'toe');

        appendLog(fig,'[MAIN] Building embedded TimeOfEvents...');
        UD.ui.toe.status.Text = 'Building TimeOfEvents...';
        drawnow;

        usvPath = '';
        if isFileSafe(exp.usvShifted)
            usvPath = exp.usvShifted;
        elseif isFileSafe(exp.usvMat)
            usvPath = exp.usvMat;
        end

        UD.modules.toe = TimesOfEventsV3('TTLcsv', exp.ttlCsv, 'PhotometryCsv', exp.photoCsv, 'USVmat', usvPath, 'Parent', UD.ui.toe.host);

        UD.ui.toe.status.Text = 'TimeOfEvents ready.';

    elseif strcmpi(whichViewer,'browser')
        exp = UD.S.main;
        requireFile(exp.fpMat,'Corrected FP MAT (MAIN)');

        doClearViewer(fig,'browser');

        % Optional TTL + USV
        ttlPath = '';
        if isFileSafe(exp.ttlCsv)
            ttlPath = exp.ttlCsv;
        end

        usvPath = '';
        if isFileSafe(exp.usvShifted)
            usvPath = exp.usvShifted;
        elseif isFileSafe(exp.usvMat)
            usvPath = exp.usvMat;
        end

        appendLog(fig,'[MAIN] Building embedded Browser...');
        UD.ui.browser.status.Text = 'Building Browser...';
        drawnow;

        UD.modules.browser = FP_TTL_USV_Browser_app(exp.fpMat, ttlPath, usvPath, 'Parent', UD.ui.browser.host);

        UD.ui.browser.status.Text = 'Browser ready.';

    elseif strcmpi(whichViewer,'compare')
        exp1 = toCompareStruct(UD.S.main, 'MAIN');
        exp2 = toCompareStruct(UD.S.cmp,  'SECONDARY');

        requireFile(exp1.fpMatPath,'Corrected FP MAT (MAIN)');
        requireFile(exp2.fpMatPath,'Corrected FP MAT (SECONDARY)');

        doClearViewer(fig,'compare');

        appendLog(fig,'Building embedded Compare (MAIN vs SECONDARY)...');
        UD.ui.compare.status.Text = 'Building Compare...';
        drawnow;

        UD.modules.compare = FP_TTL_USV_compare_app(exp1, exp2, 'Parent', UD.ui.compare.host);

        UD.ui.compare.status.Text = 'Compare ready.';

    elseif strcmpi(whichViewer,'usv')
        % USV summary uses RAW detections (not shifted)
        m = UD.S.main.usvMat;
        c = UD.S.cmp.usvMat;

        requireFile(m,'USV MAT (MAIN RAW)');
        requireFile(c,'USV MAT (SECONDARY RAW)');

        % Use MAIN output folder for exports
        exp = UD.S.main;
        otherOut = UD.S.cmp.outDir;
        [exp.outDir, exp.anchorPath] = fp_ttl_usv_default_outdir(exp.outDir, exp.anchorPath, '', otherOut);
        UD.S.main = exp;

        doClearViewer(fig,'usv');

        appendLog(fig,'Building embedded USV Summary (MAIN vs SECONDARY)...');
        UD.ui.usv.status.Text = 'Building USV Summary...';
        drawnow;

        exportDir = fullfile(exp.outDir,'USV_Exports');

        UD.modules.usv = USV_summary_dashboard(m, c, ...
            'Parent', UD.ui.usv.host, ...
            'ExportDir', exportDir, ...
            'WriteExcel', true, ...
            'MakeUI', true);

        UD.ui.usv.status.Text = sprintf('USV Summary ready. ExportDir: %s', exportDir);

    else
        return
    end

    fig.UserData = UD;

catch ME
    appendLog(fig, sprintf('[Viewer %s] ERROR: %s', whichViewer, ME.message));
end

end

function doClearViewer(fig, whichViewer)

UD = fig.UserData;

if strcmpi(whichViewer,'toe')
    delete(allchild(UD.ui.toe.host));
    UD.modules.toe = [];
    UD.ui.toe.status.Text = '';

elseif strcmpi(whichViewer,'browser')
    delete(allchild(UD.ui.browser.host));
    UD.modules.browser = [];
    UD.ui.browser.status.Text = '';

elseif strcmpi(whichViewer,'compare')
    delete(allchild(UD.ui.compare.host));
    UD.modules.compare = [];
    UD.ui.compare.status.Text = '';

elseif strcmpi(whichViewer,'usv')
    delete(allchild(UD.ui.usv.host));
    UD.modules.usv = [];
    UD.ui.usv.status.Text = '';
end

fig.UserData = UD;

end

%% ========================== UI REFRESH + STATE HELPERS ==========================

function refreshUI(fig)
% refreshUI
% ---------
% Writes current state (UD.S.main / UD.S.cmp) back into UI widgets:
%   - file path edit fields
%   - output folder
%   - status labels (USV calls + mapping)
%   - summary table

UD = fig.UserData;

% Update derived stats
UD.S.main = updateStats(UD.S.main);
UD.S.cmp  = updateStats(UD.S.cmp);

% Fill panel fields
setExpPanelFields(UD.ui.main, UD.S.main);
setExpPanelFields(UD.ui.cmp,  UD.S.cmp);

% Update summary table
UD.ui.summary.tbl.Data = buildSummaryTable(UD.S.main, UD.S.cmp);

fig.UserData = UD;

end

function setExpPanelFields(ui, exp)

ui.efPhoto.Value  = toChar(exp.photoCsv);
ui.efTTL.Value    = toChar(exp.ttlCsv);
ui.efWav.Value    = toChar(exp.ttlWav);
ui.efUSV.Value    = toChar(exp.usvMat);
ui.efOutDir.Value = toChar(exp.outDir);
ui.efFPmat.Value  = toChar(exp.fpMat);
ui.efSync.Value   = toChar(exp.syncXlsx);
ui.efUSVsh.Value  = toChar(exp.usvShifted);

ui.lblStatus.Text = makeStatusText(exp);

end

function t = buildSummaryTable(m, c)

items = {
    'Raw photometry CSV'
    'TTLBox CSV'
    'TTL WAV'
    'USV MAT'
    'Output folder'
    'Corrected FP MAT'
    'Sync mapping XLSX'
    'Shifted USV MAT'
    'Sync mapping (a | b)'
    };

t = cell(numel(items), 3);
for i = 1:numel(items)
    t{i,1} = items{i};
end

t{1,2} = shortPath(m.photoCsv);
t{2,2} = shortPath(m.ttlCsv);
t{3,2} = shortPath(m.ttlWav);
t{4,2} = shortPath(m.usvMat);
t{5,2} = shortPath(m.outDir);
t{6,2} = shortPath(m.fpMat);
t{7,2} = shortPath(m.syncXlsx);
t{8,2} = shortPath(m.usvShifted);
t{9,2} = mapStr(m);

t{1,3} = shortPath(c.photoCsv);
t{2,3} = shortPath(c.ttlCsv);
t{3,3} = shortPath(c.ttlWav);
t{4,3} = shortPath(c.usvMat);
t{5,3} = shortPath(c.outDir);
t{6,3} = shortPath(c.fpMat);
t{7,3} = shortPath(c.syncXlsx);
t{8,3} = shortPath(c.usvShifted);
t{9,3} = mapStr(c);

end

function s = mapStr(exp)
if isfinite(exp.lastMap.a) && isfinite(exp.lastMap.b)
    s = sprintf('%.12g | %.6g', exp.lastMap.a, exp.lastMap.b);
else
    s = '';
end
end

function exp = initExpState()
exp = struct();

exp.photoCsv     = '';
exp.fpMat        = '';
exp.ttlCsv       = '';
exp.ttlWav       = '';
exp.usvMat       = '';
exp.syncXlsx     = '';
exp.usvShifted   = '';
exp.overviewXlsx = '';
exp.eventLockedXlsx = '';
exp.rewardMetricsXlsx = '';
exp.rewardBinsXlsx = '';

exp.outDir     = '';
exp.anchorPath = '';

exp.lastMap = struct('a',NaN,'b',NaN);

exp.stats = struct();
exp.stats.usvCalls = NaN;
exp.stats.usvStamp = '';

end

function exp = updateStats(exp)

% Read mapping from XLSX if needed
needMap = (~isfinite(exp.lastMap.a) || ~isfinite(exp.lastMap.b));
if needMap && ~isempty(exp.syncXlsx) && isFileSafe(exp.syncXlsx)
    [a,b] = readMappingAB(exp.syncXlsx);
    if isfinite(a), exp.lastMap.a = a; end
    if isfinite(b), exp.lastMap.b = b; end
end

% Choose USV file (shifted preferred)
usvPath = '';
if isFileSafe(exp.usvShifted)
    usvPath = exp.usvShifted;
elseif isFileSafe(exp.usvMat)
    usvPath = exp.usvMat;
end

if isempty(usvPath)
    exp.stats.usvStamp = '';
    exp.stats.usvCalls = NaN;
else
    if ~strcmp(exp.stats.usvStamp, usvPath)
        exp.stats.usvStamp = usvPath;
        exp.stats.usvCalls = countUSVcalls(usvPath);
    end
end

end

function txt = makeStatusText(exp)

usvName = '-';
if ~isempty(exp.usvMat)
    try
        [~,usvName] = fileparts(exp.usvMat);
    catch
    end
end

if isfinite(exp.stats.usvCalls)
    txt = sprintf('%s | USV calls: %d', usvName, round(exp.stats.usvCalls));
else
    txt = sprintf('%s | USV calls: -', usvName);
end

end

function [a,b] = readMappingAB(syncXlsx)

a = NaN;
b = NaN;

try
    Ts = readtable(syncXlsx, 'Sheet','sync_mapping');
    if ~all(ismember({'Field','Value'}, Ts.Properties.VariableNames))
        return
    end

    fields = Ts.Field;
    values = Ts.Value;

    % Find "a (drift)" and "b (s)" by simple loop
    for i = 1:height(Ts)
        f = strtrim(lower(string(fields{i})));
        if strcmp(f,'a (drift)')
            a = str2double(string(values{i}));
        elseif strcmp(f,'b (s)')
            b = str2double(string(values{i}));
        end
    end

catch
end

end

function n = countUSVcalls(matPath)
% Count accepted calls in DeepSqueak MAT.

n = NaN;

try
    S = load(matPath);

    % 1) Find the Calls table
    Calls = [];
    if isfield(S,'Calls')
        Calls = S.Calls;
    else
        fn = fieldnames(S);
        for k = 1:numel(fn)
            if istable(S.(fn{k}))
                Calls = S.(fn{k});
                break
            end
        end
    end

    if isempty(Calls)
        return
    end

    % 2) Convert struct -> table if needed
    if isstruct(Calls)
        Calls = struct2table(Calls);
    end
    if ~istable(Calls)
        return
    end

    % 3) Keep only accepted calls if column "Accept" exists
    hasAccept = any(strcmpi(Calls.Properties.VariableNames,'Accept'));
    if hasAccept
        av = Calls.Accept;
        try
            keep = logical(av);
        catch
            keep = av ~= 0;
        end
        keep = keep(:);
        keep(isnan(double(keep))) = false;

        Calls = Calls(keep,:);
    end

    % 4) Remove Noise rows if a label column exists
    labelCandidates = {'Type','Label','AcceptedType','CallType','Category','Class','Classification'};
    labelVar = '';

    for k = 1:numel(labelCandidates)
        nameK = labelCandidates{k};
        idx = find(strcmpi(Calls.Properties.VariableNames, nameK), 1);
        if ~isempty(idx)
            labelVar = Calls.Properties.VariableNames{idx};
            break
        end
    end

    if ~isempty(labelVar)
        lab = string(Calls.(labelVar));
        isNoise = contains(upper(strtrim(lab)),'NOISE');
        Calls = Calls(~isNoise,:);
    end

    n = height(Calls);

catch
    n = NaN;
end

end

function requireFile(p, label)
% requireFile
% -----------
% Throws a readable error if a required file path is empty or does not exist.
% We use this before running a pipeline step so the user gets a clear message.

if ~isFileSafe(p)
    error('Missing/invalid file for: %s', label);
end
end

function tf = isFileSafe(p)

tf = false;

try
    if isempty(p), return; end
    if isnumeric(p) && isequal(p,0), return; end

    if iscell(p)
        if isempty(p), return; end
        p = p{1};
    end

    if isstring(p)
        if ~isscalar(p), return; end
        if strlength(p) == 0, return; end
        p = char(p);
    end

    if ischar(p)
        tf = isfile(p);
    end

catch
    tf = false;
end

end

function tf = isFolderSafe(p)

tf = false;

try
    if isempty(p), return; end
    if isnumeric(p) && isequal(p,0), return; end

    if iscell(p)
        if isempty(p), return; end
        p = p{1};
    end

    if isstring(p)
        if ~isscalar(p), return; end
        if strlength(p) == 0, return; end
        p = char(p);
    end

    if ischar(p)
        tf = isfolder(p);
    end

catch
    tf = false;
end

end

function d = suggestedDir(exp)

% Try outDir first
if ~isempty(exp.outDir) && isFolderSafe(exp.outDir)
    d = exp.outDir;
    return
end

% Then anchorPath
if ~isempty(exp.anchorPath)
    if isFolderSafe(exp.anchorPath)
        d = exp.anchorPath;
        return
    end
    try
        d = fileparts(exp.anchorPath);
        if ~isempty(d), return; end
    catch
    end
end

% Then input files
if isFileSafe(exp.photoCsv), d = fileparts(exp.photoCsv); return; end
if isFileSafe(exp.usvMat),   d = fileparts(exp.usvMat);   return; end
if isFileSafe(exp.ttlCsv),   d = fileparts(exp.ttlCsv);   return; end
if isFileSafe(exp.ttlWav),   d = fileparts(exp.ttlWav);   return; end

d = pwd;

end

function s = toCompareStruct(exp, label)

s = struct();
s.label = label;

s.fpMatPath  = exp.fpMat;
s.ttlCsvPath = exp.ttlCsv;

% Prefer shifted, but fallback to raw
if isFileSafe(exp.usvShifted)
    s.usvMatPath = exp.usvShifted;
else
    s.usvMatPath = exp.usvMat;
end

end

function tag = expTag(which)
if strcmpi(which,'main')
    tag = 'MAIN';
else
    tag = 'SECONDARY';
end
end

function appendLog(fig, msg)
% appendLog
% ---------
% Adds one line to the Log tab text area.
% Also keeps a small in-memory history in UD.logLines.

try
    UD = fig.UserData;

    ts = datestr(now,'HH:MM:SS');
    newLine = sprintf('%s  %s', ts, msg);

    UD.ui.logArea.Value = [UD.ui.logArea.Value; {newLine}];

    fig.UserData = UD;
    drawnow limitrate
catch
end

end

function openFolder(d)

if ispc
    winopen(d);
elseif ismac
    system(sprintf('open "%s"', d));
else
    system(sprintf('xdg-open "%s"', d));
end

end

function c = toChar(x)
if isempty(x)
    c = '';
else
    c = char(string(x));
end
end

function s = shortPath(p)
% Shorten long paths for table display.

if isempty(p)
    s = '';
    return
end

try
    p = char(string(p));
catch
    s = '';
    return
end

maxLen = 90;

if numel(p) <= maxLen
    s = p;
else
    tail = p(end-maxLen+1:end);
    s = ['...' tail];
end

end

function col = getColors()
% getColors
% ---------
% UI palette + font choices.
% Only affects appearance (no functional impact).

col = struct();

% Backgrounds
col.Figure = [0.94 0.95 0.98];   % soft cool background
col.Panel  = [0.98 0.98 0.99];   % near-white panels
col.Field  = [1.00 1.00 1.00];   % pure white input fields

% Text
col.Text   = [0.10 0.12 0.16];

% Fonts (Windows-friendly)
col.FontName     = 'Segoe UI';
col.MonoFontName = 'Consolas';
col.FontSize     = 12;

% Table zebra rows
col.TableRowA = [1.00 1.00 1.00];
col.TableRowB = [0.96 0.97 0.99];

% Buttons
col.BtnPrimaryBG = [0.12 0.45 0.86];   % primary blue
col.BtnPrimaryFG = [1 1 1];

col.BtnBrowseBG  = [0.35 0.36 0.40];   % browse dark gray
col.BtnBrowseFG  = [1 1 1];

col.BtnInfoBG    = [0.10 0.62 0.58];   % teal
col.BtnInfoFG    = [1 1 1];

col.BtnWarnBG    = [0.98 0.68 0.16];   % orange
col.BtnWarnFG    = [0.10 0.10 0.10];

col.BtnDangerBG  = [0.86 0.26 0.26];   % red
col.BtnDangerFG  = [1 1 1];

col.BtnNeutralBG = [0.90 0.91 0.93];   % light gray
col.BtnNeutralFG = [0.10 0.12 0.16];

end
