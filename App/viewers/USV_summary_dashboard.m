function out = USV_summary_dashboard(varargin)
% USV_summary_dashboard (PASS 2: extra-declustered + heavily commented)
% -------------------------------------------------------------------------
% PURPOSE
%   Compare TWO DeepSqueak detection MAT files (top vs bottom) and show:
%     - counts per USV category (16 categories including "USV")
%     - a total count that includes a small set of "extra" labels (Noise/Misc/22k)
%     - optional Excel export (one file per recording) of a cleaned Calls table
%
% IMPORTANT
%   - This is a VIEWER/DASHBOARD. It does not change your pipeline deliverables.
%   - The app/pipeline creates deliverables like SYNC_MAPPING.xlsx, SHIFTED.mat, etc.
%   - This dashboard only reads MAT files and optionally exports Excel/PNG.
%
% DESIGN GOAL (your request)
%   - Written like a careful student:
%       * explicit intermediate variables
%       * simple loops (no arrayfun/cellfun tricks)
%       * no inputParser (manual Name-Value parsing)
%       * lots of comments (step-by-step)
%
% -------------------------------------------------------------------------
% USAGE EXAMPLES
%   1) Recommended (no popups, app-safe):
%      out = USV_summary_dashboard(file1, file2, ...
%           'Parent', app.TabUSV, ...
%           'ExportDir', fullfile(app.OutDir,'USV_Exports'), ...
%           'WriteExcel', true, ...
%           'MakeUI', true);
%
%   2) Standalone + interactive selection dialogs:
%      out = USV_summary_dashboard('Interactive', true);
%
% -------------------------------------------------------------------------
% OUTPUT (struct)
%   out.exportDir, out.exportFiles, out.recNames,
%   out.catData, out.extraData,
%   out.categories, out.prettyNames,
%   out.inputs, out.ui
% -------------------------------------------------------------------------


%% =====================================================================
% 1) READ POSITIONAL INPUTS (if the first two args are file paths)
% =====================================================================
file1 = "";
file2 = "";

% We keep the remaining args in "args" and parse them as Name-Value pairs.
args = varargin;

% If the first two args are text scalars, treat them as file paths.
if numel(args) >= 2
    if isTextScalar(args{1}) && isTextScalar(args{2})
        file1 = string(args{1});     % input file #1
        file2 = string(args{2});     % input file #2
        args  = args(3:end);         % remove those two from the Name-Value list
    end
end


%% =====================================================================
% 2) DEFAULT OPTIONS (what happens if user does not pass Name-Value inputs)
% =====================================================================
opt = struct();

% Inputs (may have come from positional arguments above)
opt.File1 = file1;
opt.File2 = file2;

% Embedding
opt.Parent = [];            % if empty => create standalone uifigure
opt.MakeUI = true;          % if false => compute counts but do not build UI

% Interaction
opt.Interactive = false;    % if true => allow file selection dialogs
opt.AllowFileDialogs = [];  % default: allow dialogs only when NOT embedded

% Export behavior
opt.ExportDir = "";         % where to write Excel exports (if enabled)
opt.WriteExcel = true;      % if true => export one Excel per recording
opt.ExportPngDir = "";      % where to export PNG if user clicks button

% Logging
opt.Verbose = false;


%% =====================================================================
% 3) PARSE NAME-VALUE PAIRS (manual, explicit)
% =====================================================================
% We require pairs: 'Name1',Value1,'Name2',Value2,...
if mod(numel(args), 2) ~= 0
    error('USV_summary_dashboard:NameValue', ...
        'Name/value inputs must come in pairs (even number of arguments).');
end

k = 1;
while k <= numel(args)

    % Read one pair (name, value)
    nameIn = args{k};
    valIn  = args{k+1};
    k = k + 2;

    % Validate that the name is text
    if ~isTextScalar(nameIn)
        error('USV_summary_dashboard:NameValue', ...
            'Parameter name must be text. Got: %s', class(nameIn));
    end

    % Normalize name (lowercase string, trimmed)
    name = lower(strtrim(string(nameIn)));

    % Apply option
    if name == "file1"
        opt.File1 = string(valIn);

    elseif name == "file2"
        opt.File2 = string(valIn);

    elseif name == "parent"
        opt.Parent = valIn;

    elseif name == "interactive"
        opt.Interactive = logical(valIn);

    elseif name == "allowfiledialogs"
        opt.AllowFileDialogs = valIn;

    elseif name == "exportdir"
        opt.ExportDir = string(valIn);

    elseif name == "writeexcel"
        opt.WriteExcel = logical(valIn);

    elseif name == "makeui"
        opt.MakeUI = logical(valIn);

    elseif name == "exportpngdir"
        opt.ExportPngDir = string(valIn);

    elseif name == "verbose"
        opt.Verbose = logical(valIn);

    else
        error('USV_summary_dashboard:UnknownParam', ...
            'Unknown parameter: %s', name);
    end
end


%% =====================================================================
% 4) DECIDE WHETHER FILE DIALOGS ARE ALLOWED
% =====================================================================
Parent = opt.Parent;

% Default rule:
%   - if embedded (Parent not empty) => NO dialogs by default
%   - if standalone => dialogs allowed
if isempty(opt.AllowFileDialogs)
    allowDialogs = isempty(Parent);
else
    allowDialogs = logical(opt.AllowFileDialogs);
end


%% =====================================================================
% 5) RESOLVE OUTPUT DIRECTORIES (ExportDir + ExportPngDir)
% =====================================================================
% baseDir = folder where this script lives (if possible)
baseDir = string(fileparts(mfilename('fullpath')));
if strlength(baseDir) == 0
    baseDir = string(pwd);
end

% ExportDir default: <baseDir>/USV_Exports
exportDir = string(opt.ExportDir);
if strlength(exportDir) == 0
    exportDir = string(fullfile(baseDir, 'USV_Exports'));
end

% Ensure ExportDir exists
if ~isfolder(exportDir)
    mkdir(exportDir);
end

% Export PNG dir default: baseDir (so user can find the image easily)
exportPngDir = string(opt.ExportPngDir);
if strlength(exportPngDir) == 0
    exportPngDir = baseDir;
end

% Ensure PNG folder exists
if ~isfolder(exportPngDir)
    mkdir(exportPngDir);
end


%% =====================================================================
% 6) RESOLVE INPUT FILES (File1 + File2)
% =====================================================================
file1 = string(opt.File1);
file2 = string(opt.File2);

% If one of them is missing, decide whether we can prompt for selection.
if strlength(file1) == 0 || strlength(file2) == 0

    if opt.Interactive && allowDialogs

        % Ask user to pick file #1
        [fn1, p1] = uigetfile({'*.mat','DeepSqueak detection MAT (*.mat)'}, ...
            'Select Detection MAT #1 (TOP plot)');
        if isequal(fn1, 0)
            error('Cancelled: no file #1 selected.');
        end
        file1 = string(fullfile(p1, fn1));

        % Ask user to pick file #2
        [fn2, p2] = uigetfile({'*.mat','DeepSqueak detection MAT (*.mat)'}, ...
            'Select Detection MAT #2 (BOTTOM plot)');
        if isequal(fn2, 0)
            error('Cancelled: no file #2 selected.');
        end
        file2 = string(fullfile(p2, fn2));

    else
        % Non-interactive mode: file paths must be provided.
        error(['USV_summary_dashboard requires two detection MAT files ' ...
               '(File1/File2 or 2 positional args) in non-interactive mode.']);
    end
end

% Final safety check: files must exist
if ~isfile(file1)
    error('File1 not found: %s', file1);
end
if ~isfile(file2)
    error('File2 not found: %s', file2);
end


%% =====================================================================
% 7) CONFIGURE CATEGORY LISTS (what we count on the plot)
% =====================================================================
% 16 categories we display and count into catData.
% IMPORTANT: only these 16 are counted as "cat totals".
REF_ORDER = upper(string({ ...
    'COMPLEX','UPWARD_RAMP','DOWNWARD_RAMP','FLAT','SHORT','SPLIT', ...
    'STEP_UP','STEP_DOWN','MULTI_STEP','TRILL','FLAT_TRILL_COMBINATION', ...
    'TRILL_WITH_JUMPS','INVERTED_U','COMPOSITE','UNCLEAR', ...
    'USV'}));

% Extras: labels that count only toward "All calls" (not plotted categories)
% NOTE: USV is NOT included here.
EXTRA_SET = { ...
    'NOISE','MISC','MISCELLANEOUS','NOISEUSV', ...
    '22KHZ','22KHZCALLS','K22','KHZ22'};

% Normalize category names (once) so we normalize the Calls labels only once too.
nCats = numel(REF_ORDER);

refNorm = strings(nCats, 1);
for i = 1:nCats
    refNorm(i) = normStr(REF_ORDER(i));  % remove punctuation and uppercase
end

extraNorm = strings(numel(EXTRA_SET), 1);
for i = 1:numel(EXTRA_SET)
    extraNorm(i) = normStr(EXTRA_SET{i});
end

% Pretty x-axis labels for plotting (more readable)
prettyNames = REF_ORDER;                 % start from the reference names
prettyNames = replace(prettyNames, "_", " ");

% Fix a few that look nicer with spaces/hyphens
prettyNames = replace(prettyNames, "UPWARD RAMP", "UPWARD RAMP");
prettyNames = replace(prettyNames, "DOWNWARD RAMP", "DOWNWARD RAMP");
prettyNames = replace(prettyNames, "STEP UP", "STEP UP");
prettyNames = replace(prettyNames, "STEP DOWN", "STEP DOWN");
prettyNames = replace(prettyNames, "MULTI STEP", "MULTI-STEP");
prettyNames = replace(prettyNames, "FLAT TRILL COMBINATION", "FLAT/TRILL COMBINATION");
prettyNames = replace(prettyNames, "TRILL WITH JUMPS", "TRILL WITH JUMPS");
prettyNames = replace(prettyNames, "INVERTED U", "INVERTED U");

% Data arrays:
%   - catData is 2 x nCats (top file row 1, bottom file row 2)
%   - extraData is 2 x 1 (sum of "extra" labels)
catData   = zeros(2, nCats);
extraData = zeros(2, 1);


%% =====================================================================
% 8) PROCESS BOTH FILES (load Calls -> standardize -> count + export)
% =====================================================================
files = {char(file1); char(file2)};
recNames = strings(2, 1);        % recording base names (for titles)
exportFiles = strings(1, 2);     % Excel exports (optional)

for f = 1:2

    % Path for this file
    srcPath = files{f};

    % Base name (no extension) used for labels and output names
    [~, baseName] = fileparts(srcPath);
    recNames(f) = string(baseName);

    % ----------------- 8.1) Load Calls table from MAT -----------------
    Calls = loadCallsTable(srcPath);

    if isempty(Calls) || height(Calls) == 0
        warning('No usable Calls found in: %s', srcPath);
        continue;
    end

    % ----------------- 8.2) Standardize labels + accept filter -----------------
    % This:
    %   - chooses a label column (prefers Type)
    %   - if Accept column exists, keeps only accepted calls
    %   - ensures CallsStd.Type exists as a string label column
    [CallsStd, labelsAccepted] = standardizeCallsAndLabels(Calls);

    % ----------------- 8.3) Optional Excel export -----------------
    if opt.WriteExcel

        % Clean for export only (removes Noise rows, expands Box column, etc.)
        CallsOut = cleanCallsForExport_student(CallsStd);

        % Safe filename for Excel export
        safeName = regexprep(baseName, '[^\w\d-]+', '_');
        outXlsx  = fullfile(exportDir, safeName + ".xlsx");

        % Try writing Excel
        try
            writetable(CallsOut, outXlsx, 'Sheet', 'Calls');
            exportFiles(f) = string(outXlsx);

            if opt.Verbose
                fprintf('[Export] %s -> %s (%d calls)\n', baseName, outXlsx, height(CallsOut));
            end
        catch ME
            warning('[Export] Failed writing %s: %s', outXlsx, ME.message);
        end
    end

    % ----------------- 8.4) Count categories/extras (accepted calls only) -----------------
    if isempty(labelsAccepted)
        continue;
    end

    % Normalize each accepted label ONCE
    L = strings(numel(labelsAccepted), 1);
    for i = 1:numel(labelsAccepted)
        L(i) = normStr(labelsAccepted(i));
    end

    % Scan every label and classify it
    for i = 1:numel(L)

        thisLab = L(i);

        % 1) Try to match to one of the 16 plotted categories
        matchedCat = false;

        for c = 1:nCats
            if thisLab == refNorm(c)
                catData(f, c) = catData(f, c) + 1;
                matchedCat = true;
                break;
            end
        end

        % If matched to a main category, do NOT check extras
        if matchedCat
            continue;
        end

        % 2) Otherwise check if it is part of the "extras" list
        for e = 1:numel(extraNorm)
            if thisLab == extraNorm(e)
                extraData(f, 1) = extraData(f, 1) + 1;
                break;
            end
        end

        % 3) If it matches neither, we ignore it (this keeps original behavior)
    end

end


%% =====================================================================
% 9) BUILD DASHBOARD UI (optional)
% =====================================================================
ui = struct();

if opt.MakeUI

    % 9.1) Create a standalone figure OR embed into Parent
    if isempty(Parent)
        fig = uifigure( ...
            'Name', 'USV — Compare 2 recordings (TOP/BOTTOM)', ...
            'Color', 'w', ...
            'Position', [120 60 1280 740]);
        root = fig;
    else
        root = uipanel(Parent, ...
            'BorderType', 'none', ...
            'BackgroundColor', 'w', ...
            'Units', 'normalized', ...
            'Position', [0 0 1 1]);
        fig = ancestor(root, 'figure');
    end

    % 9.2) Layout: header row + button row + plot row
    gMain = uigridlayout(root, [3 1]);
    gMain.RowHeight = {34, 34, '1x'};
    gMain.ColumnWidth = {'1x'};
    gMain.Padding = [10 10 10 10];
    gMain.BackgroundColor = 'w';

    % ---- Header row (two labels: top file name, bottom file name) ----
    gHdr = uigridlayout(gMain, [1 2]);
    gHdr.ColumnWidth = {'1x', '1x'};
    gHdr.RowHeight = {34};
    gHdr.Padding = [0 0 0 0];
    gHdr.BackgroundColor = 'w';

    lblTop = uilabel(gHdr, ...
        'Text', "Top plot (File #1): " + recNames(1), ...
        'FontWeight', 'bold', ...
        'HorizontalAlignment', 'left');

    lblBot = uilabel(gHdr, ...
        'Text', "Bottom plot (File #2): " + recNames(2), ...
        'FontWeight', 'bold', ...
        'HorizontalAlignment', 'right');

    % ---- Button row ----
    gBtn = uigridlayout(gMain, [1 3]);
    gBtn.ColumnWidth = {180, '1x', 1};   % first col for button, rest filler
    gBtn.RowHeight = {34};
    gBtn.Padding = [0 0 0 0];
    gBtn.BackgroundColor = 'w';

    btnExport = uibutton(gBtn, 'Text', 'Export PNG (300 dpi)');
    btnExport.Layout.Row = 1;
    btnExport.Layout.Column = 1;

    % ---- Plots row (two axes stacked) ----
    gPlots = uigridlayout(gMain, [2 1]);
    gPlots.RowHeight = {'1x', '1x'};
    gPlots.Padding = [0 0 0 0];
    gPlots.BackgroundColor = 'w';

    % Top axis
    axTop = uiaxes(gPlots);
    grid(axTop, 'on');
    box(axTop, 'off');
    ylabel(axTop, 'Count');

    % Bottom axis
    axBot = uiaxes(gPlots);
    grid(axBot, 'on');
    box(axBot, 'off');
    ylabel(axBot, 'Count');

    % 9.3) Draw plots (fixed Top/Bottom)
    local_redraw_fixed_student(axTop, 1, catData, extraData, recNames, prettyNames);
    local_redraw_fixed_student(axBot, 2, catData, extraData, recNames, prettyNames);

    % 9.4) Export callback
    btnExport.ButtonPushedFcn = @(~,~) localExportPNG(gPlots, exportPngDir, recNames);

    % 9.5) Pack UI handles
    ui = struct();
    ui.Figure       = fig;
    ui.Root         = root;
    ui.MainGrid     = gMain;
    ui.AxTop        = axTop;
    ui.AxBottom     = axBot;
    ui.ExportButton = btnExport;
    ui.HeaderTop    = lblTop;
    ui.HeaderBottom = lblBot;
end


%% =====================================================================
% 10) OUTPUT STRUCT (keeps the same fields expected by the Master App)
% =====================================================================
out = struct();

% Export info
out.exportDir   = string(exportDir);
out.exportFiles = exportFiles;

% Recording names + data arrays
out.recNames    = recNames;
out.catData     = catData;
out.extraData   = extraData;

% Category lists for plotting/debugging
out.categories  = REF_ORDER;
out.prettyNames = prettyNames;

% Inputs (for traceability)
out.inputs = struct();
out.inputs.file1 = string(file1);
out.inputs.file2 = string(file2);

% UI handles (if created)
out.ui = ui;

end


%% =====================================================================
% HELPER FUNCTIONS (kept at bottom, small + single-purpose)
% =====================================================================

function tf = isTextScalar(x)
% Return true only for a single string or a row char array.
tf = (ischar(x) && isrow(x)) || (isstring(x) && isscalar(x));
end

function Calls = loadCallsTable(matPath)
% Load Calls from a DeepSqueak detection MAT.
% The "Calls" field can be:
%   - a table
%   - a struct array (convert via struct2table)
%   - missing (return empty table)

Calls = table();   % default empty

% Load the MAT file into a struct
S = load(matPath);

% If Calls field doesn't exist, stop
if ~isfield(S, 'Calls')
    return;
end

C = S.Calls;

% Calls already a table
if istable(C)
    Calls = C;
    return;
end

% Calls as struct -> convert to table (best effort)
if isstruct(C)
    try
        Calls = struct2table(C);
    catch
        try
            Calls = struct2table(C, 'AsArray', true);
        catch
            Calls = table();
        end
    end
end
end

function [CallsStd, labelsAllAccepted] = standardizeCallsAndLabels(Calls)
% Standardize DeepSqueak Calls table into a consistent format:
%   - ensures CallsStd.Type exists and is a string label column
%   - if Accept column exists, keeps only accepted rows
%   - returns labelsAllAccepted as a string vector

CallsStd = Calls;

% 1) Find a label column (Type preferred)
labelCandidates = {'Type','Label','AcceptedType','CallType','Category','Class','Classification'};
labelVar = "";

for k = 1:numel(labelCandidates)
    idx = find(strcmpi(CallsStd.Properties.VariableNames, labelCandidates{k}), 1, 'first');
    if ~isempty(idx)
        labelVar = CallsStd.Properties.VariableNames{idx};
        break;
    end
end

% If no label column exists, create one called Type
if strlength(string(labelVar)) == 0
    CallsStd.Type = repmat("Unlabeled", height(CallsStd), 1);
    labelVar = "Type";
end

% 2) If Accept exists, keep only accepted rows
idxA = find(strcmpi(CallsStd.Properties.VariableNames, 'Accept'), 1, 'first');

if ~isempty(idxA)

    % Read Accept column
    acceptVarName = CallsStd.Properties.VariableNames{idxA};
    av = CallsStd.(acceptVarName);

    % Build keep mask
    keepMask = false(height(CallsStd), 1);

    % Accept can be logical, numeric, or text
    if islogical(av)
        keepMask = av(:);

    elseif isnumeric(av)
        keepMask = (av(:) ~= 0);

    else
        s = lower(strtrim(string(av)));
        keepMask = (s == "true") | (s == "1") | (s == "yes") | (s == "accepted");
    end

    % Apply mask
    CallsStd = CallsStd(keepMask, :);
end

% 3) Extract labels from labelVar (after filtering)
labels = string(CallsStd.(labelVar));
labels = strtrim(labels);
labels(labels == "") = "Unlabeled";

% Ensure CallsStd.Type exists and matches extracted labels
CallsStd.Type = labels;

% Return accepted-only labels as column vector
labelsAllAccepted = labels(:);
end

function CallsOut = cleanCallsForExport_student(CallsStd)
% Prepare a Calls table for Excel export.
% IMPORTANT: this does NOT affect counting; it only affects the exported file.

CallsOut = CallsStd;

% 1) Remove Noise rows (export only)
typeStr = string(CallsOut.Type);
typeStr = strtrim(typeStr);

keepMask = true(height(CallsOut), 1);
for i = 1:height(CallsOut)
    if contains(upper(typeStr(i)), "NOISE")
        keepMask(i) = false;
    end
end
CallsOut = CallsOut(keepMask, :);

% 2) Drop Accept column (export doesn't need it)
idxA = find(strcmpi(CallsOut.Properties.VariableNames, 'Accept'), 1, 'first');
if ~isempty(idxA)
    CallsOut.(CallsOut.Properties.VariableNames{idxA}) = [];
end

% 3) Expand Box -> BeginTime_s / MinFreq_kHz / Duration_ms / FreqRange_kHz
idxB = find(strcmpi(CallsOut.Properties.VariableNames, 'Box'), 1, 'first');
if ~isempty(idxB)

    Braw = CallsOut.(CallsOut.Properties.VariableNames{idxB});
    B = [];

    % If numeric already, use directly
    if isnumeric(Braw)
        B = Braw;

    % If cell, try to convert each row to numeric [t, f, dur, range]
    elseif iscell(Braw)

        n = height(CallsOut);
        temp = nan(n, 4);

        for r = 1:n
            bi = Braw{r};

            % Unwrap nested single-element cell layers
            while iscell(bi) && numel(bi) == 1
                bi = bi{1};
            end

            if isnumeric(bi) && numel(bi) >= 4
                temp(r, 1) = bi(1);
                temp(r, 2) = bi(2);
                temp(r, 3) = bi(3);
                temp(r, 4) = bi(4);
            end
        end

        if any(~isnan(temp(:,1)))
            B = temp;
        end
    end

    % If we succeeded, create the new columns
    if isnumeric(B) && ismatrix(B) && size(B,2) >= 4
        CallsOut.BeginTime_s   = B(:,1);
        CallsOut.MinFreq_kHz   = B(:,2);
        CallsOut.Duration_ms   = 1000 * B(:,3);
        CallsOut.FreqRange_kHz = B(:,4);
    end

    % Remove the Box column after expansion
    CallsOut.(CallsOut.Properties.VariableNames{idxB}) = [];
end

% 4) Derived columns (EndTime, Duration_s, HighFreq_kHz)
if all(ismember({'BeginTime_s','Duration_ms'}, CallsOut.Properties.VariableNames))
    CallsOut.EndTime_s  = CallsOut.BeginTime_s + (CallsOut.Duration_ms / 1000);
    CallsOut.Duration_s = CallsOut.Duration_ms / 1000;
end

if all(ismember({'MinFreq_kHz','FreqRange_kHz'}, CallsOut.Properties.VariableNames))
    CallsOut.HighFreq_kHz = CallsOut.MinFreq_kHz + CallsOut.FreqRange_kHz;
end

% 5) Rename Score -> TrustScore (clearer for humans)
idxS = find(strcmpi(CallsOut.Properties.VariableNames, 'Score'), 1, 'first');
if ~isempty(idxS)
    CallsOut.TrustScore = CallsOut.(CallsOut.Properties.VariableNames{idxS});
    CallsOut.(CallsOut.Properties.VariableNames{idxS}) = [];
end

% 6) Add CallIndex as first column (useful in Excel)
CallIndex = (1:height(CallsOut)).';
CallsOut  = addvars(CallsOut, CallIndex, 'Before', 1);
end

function sOut = normStr(sIn)
% Normalize a label so matching is stable:
%   - remove all non-alphanumeric characters
%   - uppercase everything
s = string(sIn);
s = regexprep(s, '[^a-zA-Z0-9]', '');
sOut = upper(s);
end

function local_redraw_fixed_student(ax, rowIdx, catData, extraData, recNames, pretty)
% Draw one bar chart for one file (rowIdx = 1 or 2).

% Extract the row vector of counts
data = catData(rowIdx, :);

% Sum category counts explicitly (student-style loop)
catTotal = 0;
for i = 1:numel(data)
    if ~isnan(data(i))
        catTotal = catTotal + data(i);
    end
end

% Extra labels sum (Noise/Misc/22k)
extrasSum = extraData(rowIdx, 1);

% "All calls" total = plotted categories + extras
allCallsTotal = catTotal + extrasSum;

% Title text
ttl = sprintf('%s — All calls: %d | %d-cat total: %d', ...
    recNames(rowIdx), allCallsTotal, numel(pretty), catTotal);

% Clear axis before drawing
cla(ax);

% Bar plot
h = bar(ax, data, ...
    'FaceColor', [0.20 0.75 0.20], ...
    'BarWidth', 0.55, ...
    'LineWidth', 0.8);

% Axis formatting
title(ax, ttl, 'FontSize', 14);
ylabel(ax, 'Count');

nCats = numel(pretty);
set(ax, 'XTick', 1:nCats, 'XTickLabel', pretty);
ax.XTickLabelRotation = 40;
ax.XAxis.FontSize = 12;
xlim(ax, [0.4, nCats + 0.6]);

% Y-limits: keep some headroom so value labels fit
ymax = max([1, max(data)]);
ylim(ax, [0, 1.18 * ymax]);

grid(ax, 'on');
box(ax, 'off');
ax.YAxis.FontSize = 11;

% Data tips (best effort, depends on MATLAB version)
try
    h.DataTipTemplate.DataTipRows = [ ...
        dataTipTextRow('Category', cellstr(pretty)), ...
        dataTipTextRow('Count', h.YData)];
catch
    % If this fails (older MATLAB), ignore
end

% Value labels above bars
for i = 1:nCats
    if data(i) > 0
        text(ax, i, data(i) + 0.02 * ymax, string(data(i)), ...
            'HorizontalAlignment', 'center', ...
            'FontSize', 15, ...
            'FontWeight', 'bold', ...
            'Color', [0.1 0.1 0.1]);
    end
end
end

function localExportPNG(containerHandle, outDir, recNames)
% Export the entire plot container to a PNG at 300 dpi.

try
    % Build safe filename
    base = recNames(1) + "__VS__" + recNames(2);
    base = regexprep(base, '[^\w\d-]', '_');
    fname = "USV_compare_" + base + ".png";

    % Export (300 dpi, white background)
    exportgraphics(containerHandle, fullfile(outDir, fname), ...
        'Resolution', 300, ...
        'BackgroundColor', 'white');

catch ME
    % If there is a UI figure available, show alert; else warn
    try
        uialert(ancestor(containerHandle, 'figure'), ...
            sprintf('Export failed:\n%s', ME.message), ...
            'Export PNG');
    catch
        warning('Export failed: %s', ME.message);
    end
end
end
