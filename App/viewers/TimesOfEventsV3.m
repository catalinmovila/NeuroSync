function out = TimesOfEventsV3(varargin)
% TimesOfEventsV3 (PASS 2: extra-declustered + heavily commented)
% -------------------------------------------------------------------------
% GOAL OF THIS FILE
%   Show reward-aligned photometry responses (Food vs Drug) using:
%     1) TTLBox CSV (event times)
%     2) Photometry CSV (raw LED-flipped signal)
%
% This is designed to work in TWO modes:
%   (A) Embedded in the Master App (Parent provided)
%   (B) Standalone (creates its own uifigure if Parent is empty)
%
% WHAT THIS UI DOES
%   1) Reads TTLBox events -> extracts TTL pulse widths -> classifies pulses:
%        - Food pulses: width ~ FoodPulseMs (default 40 ms)
%        - Drug pulses: width ~ DrugPulseMs (default 60 ms)
%   2) Reads photometry -> builds LED pairs (465 + 405) -> computes corrected ΔF/F:
%        - Fit 405 to 465 using polyfit (linear)
%        - dFF = (465 - fitted405) / fitted405
%   3) Extracts windows around each event -> baseline-correct each window
%   4) Plots mean ± STD for Food vs Drug, optional individual traces
%   5) Shows AUC+ (area under positive part) from 0 to +win_s
%
% IMPORTANT
%   This file produces NO external deliverable files. It is a viewer tab.
%   The deliverables are created by the pipeline steps, not this UI.
%
% -------------------------------------------------------------------------
% USAGE (embedded)
%   out = TimesOfEventsV3('TTLcsv', ttlFile, 'PhotometryCsv', photoFile, 'Parent', parentHandle);
%
% USAGE (interactive)
%   out = TimesOfEventsV3('Interactive', true, 'AllowFileDialogs', true);
%
% OUTPUT
%   out.Root, out.UIAxes, out.Controls, out.Inputs, out.Data, out.Refresh(win_s)
% -------------------------------------------------------------------------


%% =====================================================================
% 1) DEFAULT SETTINGS (what happens if user does not pass options)
% =====================================================================
args = struct();

% File inputs (the two most important inputs)
args.TTLcsv           = "";   % TTLBox CSV path (string)
args.PhotometryCsv    = "";   % photometry CSV path (string)
args.USVmat          = "";   % optional USV MAT (prefer *_SHIFTED.mat)

% UI embedding / mode flags
args.Parent           = [];   % Parent container (uitab/uipanel/uigridlayout). Empty => standalone figure
args.Interactive      = false; % if true, user can pick files via dialogs
args.AllowFileDialogs = false; % if true, allow uigetfile even if not Interactive

% TTL pulse classification settings
args.FoodPulseMs      = 40;   % expected pulse width (ms) for Food
args.DrugPulseMs      = 60;   % expected pulse width (ms) for Drug
args.TolPct           = 10;   % tolerance (%). Example: 10% means 40ms ± 4ms
args.TTLOffset_s      = 0;    % optional time offset to shift TTL times (seconds)

% Plot settings
args.DefaultWin_s     = 5;           % default plot window is ±5 seconds
args.BaselineMode     = "mean_pre";  % baseline removal inside event window
args.ShowIndividuals  = false;       % show individual event traces or only mean±std


%% =====================================================================
% 2) PARSE NAME-VALUE INPUTS (beginner-style, explicit)
% =====================================================================
% We accept arguments like:
%   TimesOfEventsV3('TTLcsv', 'C:\...\TTL Box15.csv', 'PhotometryCsv', 'C:\...\Photometry.csv', ...)
%
% We require pairs:
%   name1,value1,name2,value2,...
%
if ~isempty(varargin)

    % Must be even number of inputs
    if mod(numel(varargin), 2) ~= 0
        error('TimesOfEventsV3: Name-Value inputs must come in pairs.');
    end

    % Walk through pairs
    k = 1;
    while k <= numel(varargin)

        % Read one name-value pair
        nameIn = varargin{k};
        valIn  = varargin{k+1};

        % Validate the name is text
        if ~(ischar(nameIn) || isstring(nameIn))
            error('TimesOfEventsV3: Parameter name at position %d is not text.', k);
        end

        % Normalize key to lower-case char for simple strcmp checks
        key = lower(char(string(nameIn)));

        % Apply the option to args (explicit, no "magic")
        if strcmp(key, 'ttlcsv')
            args.TTLcsv = string(valIn);

        elseif strcmp(key, 'photometrycsv')
            args.PhotometryCsv = string(valIn);

        elseif strcmp(key, 'usvmat') || strcmp(key, 'usvmatpath') || strcmp(key, 'usvmatfile')
            % Optional: DeepSqueak MAT containing calls (prefer your *_SHIFTED.mat)
            args.USVmat = string(valIn);

        elseif strcmp(key, 'parent')
            args.Parent = valIn;

        elseif strcmp(key, 'interactive')
            args.Interactive = logical(valIn);

        elseif strcmp(key, 'allowfiledialogs')
            args.AllowFileDialogs = logical(valIn);

        elseif strcmp(key, 'foodpulsems')
            args.FoodPulseMs = double(valIn);

        elseif strcmp(key, 'drugpulsems')
            args.DrugPulseMs = double(valIn);

        elseif strcmp(key, 'tolpct')
            args.TolPct = double(valIn);

        elseif strcmp(key, 'ttloffset_s')
            args.TTLOffset_s = double(valIn);

        elseif strcmp(key, 'defaultwin_s')
            args.DefaultWin_s = double(valIn);

        elseif strcmp(key, 'baselinemode')
            args.BaselineMode = string(valIn);

        elseif strcmp(key, 'showindividuals')
            args.ShowIndividuals = logical(valIn);

        else
            % Unknown option => error (keep behavior strict)
            error('TimesOfEventsV3: Unknown parameter: %s', key);
        end

        % Move to next pair
        k = k + 2;
    end
end

% Normalize / clean some types after parsing
args.TTLcsv        = string(args.TTLcsv);
args.PhotometryCsv = string(args.PhotometryCsv);
args.USVmat        = string(args.USVmat);
args.BaselineMode  = string(args.BaselineMode);


%% =====================================================================
% 3) RESOLVE MISSING FILES (optional file dialogs, only if allowed)
% =====================================================================
% If user did not pass TTLcsv or PhotometryCsv, we either:
%   - error (non-interactive mode), OR
%   - prompt for files (Interactive/AllowFileDialogs mode)
%
if strlength(args.TTLcsv) == 0 || strlength(args.PhotometryCsv) == 0

    % Decide if we are allowed to pop file pickers
    wantDialogs = (args.Interactive || args.AllowFileDialogs);

    if ~wantDialogs
        error(['TimesOfEventsV3: Missing inputs. Provide TTLcsv and PhotometryCsv, ' ...
               'or set Interactive/AllowFileDialogs=true.']);
    end

    % Starting folder for dialogs
    startDir = pwd;

    % If TTL is already given, use its folder as startDir
    if strlength(args.TTLcsv) > 0
        try
            startDir = fileparts(args.TTLcsv);
        catch
            % ignore, keep pwd
        end
    end

    % ---- Pick TTLBox CSV if missing ----
    if strlength(args.TTLcsv) == 0
        [fn1, p1] = uigetfile({ ...
            '*.csv;*.CSV', 'CSV files (*.csv)'; ...
            '*.*',         'All files (*.*)'}, ...
            'Select TTL Box event log (CSV)', startDir);

        if isequal(fn1, 0)
            error('Cancelled TTL selection.');
        end

        args.TTLcsv = string(fullfile(p1, fn1));
        startDir = p1;  % next dialog starts here
    end

    % ---- Pick photometry CSV if missing ----
    if strlength(args.PhotometryCsv) == 0
        [fn2, p2] = uigetfile({ ...
            '*.csv;*.CSV', 'CSV files (*.csv)'; ...
            '*.*',         'All files (*.*)'}, ...
            'Select photometry recording (CSV)', startDir);

        if isequal(fn2, 0)
            error('Cancelled photometry selection.');
        end

        args.PhotometryCsv = string(fullfile(p2, fn2));
    end
end

% Final safety check: files must exist
if ~isfile(args.TTLcsv)
    error('TTLcsv not found: %s', args.TTLcsv);
end
if ~isfile(args.PhotometryCsv)
    error('PhotometryCsv not found: %s', args.PhotometryCsv);
end

% Optional: USV MAT may be empty; if provided but missing, ignore it.
if strlength(args.USVmat) > 0 && ~isfile(args.USVmat)
    warning('TimesOfEventsV3: USVmat not found, ignoring: %s', args.USVmat);
    args.USVmat = "";
end


%% =====================================================================
% 4) READ TTLBOX CSV -> EXTRACT PULSES -> CLASSIFY FOOD/DRUG
% =====================================================================

% Read the TTLBox table (delimiter is comma)
Tttl = readtable(args.TTLcsv, 'Delimiter', ',');

% Get numeric time column from the TTLBox CSV
% - Prefer Var4 if it exists (typical TTLBox export)
% - Else pick the numeric column with most finite values
ttlTime = localPickNumericTimeColumn(Tttl);   % numeric column vector
ttlTime = ttlTime(:);                         % force to column

% Remove NaNs and Infs
ttlTime = ttlTime(isfinite(ttlTime));

% Apply optional offset (useful if you know the TTLBox clock needs shifting)
ttlTime = ttlTime + args.TTLOffset_s;

% Extract pulses:
% TTLBox CSV often stores timestamps in ON/OFF pairs:
%   start1, end1, start2, end2, ...
% But sometimes there can be a one-row shift, so we try 2 pairing patterns
[pulseStarts_s, pulseWidths_ms] = localExtractPulsesBestPairing(ttlTime);

% Classify each pulse by width:
% "matches" means within TolPct of the target width(s)
isFood = localWidthMatches(pulseWidths_ms, args.FoodPulseMs, args.TolPct);
isDrug = localWidthMatches(pulseWidths_ms, args.DrugPulseMs, args.TolPct);

% Extract Food/Drug event start times (seconds)
foodTimes = pulseStarts_s(isFood);
drugTimes = pulseStarts_s(isDrug);


%% =====================================================================
% 5) READ PHOTOMETRY CSV -> BUILD LED PAIRS -> COMPUTE CORRECTED dFF
% =====================================================================

% Read photometry data table
T = readtable(args.PhotometryCsv, 'Delimiter', ',');

% Pull required columns (case-insensitive)
tPhoto   = double(localGetVarCI(T, {'SystemTimestamp','Timestamp','Time'})); % timestamps (seconds)
LedState = double(localGetVarCI(T, {'LedState','LEDState','Led','LED'}));    % LED code (1 or 2)

% Decide which signal column to use:
% prefer "G0" (most common), else "G1"
vars = T.Properties.VariableNames;
hasG0 = any(strcmpi(vars, 'G0'));
hasG1 = any(strcmpi(vars, 'G1'));

if hasG0
    sigName = 'G0';
elseif hasG1
    sigName = 'G1';
else
    error('Photometry: no G0 or G1 column found.');
end

% Read raw signal column
sigRaw = double(T.(localResolveVarNameCI(T, sigName)));

% Remove rows that contain NaNs/Infs in any of the key vectors
good = isfinite(tPhoto) & isfinite(LedState) & isfinite(sigRaw);
tPhoto   = tPhoto(good);
LedState = LedState(good);
sigRaw   = sigRaw(good);

% Build LED pairs:
% We want a "paired" time axis where each sample corresponds to ONE 465/405 pair
% We accept either adjacent pattern:
%   (LedState==2 then 1) OR (LedState==1 then 2)
[pairTime, sig465, sig405] = localBuildLedPairs_465_405(tPhoto, LedState, sigRaw);

% Compute sampling step (seconds) on the paired series
dt = median(diff(pairTime));
if ~isfinite(dt) || dt <= 0
    error('Photometry: invalid time step (check timestamps).');
end

% Corrected dFF:
% 1) Fit 405 to 465 (linear)
% 2) dFF = (465 - fitted405) / fitted405
p = polyfit(sig405, sig465, 1);           % slope + intercept
fitted405 = polyval(p, sig405);           % predicted 465 from 405
fitted405(fitted405 == 0) = NaN;          % avoid division by zero

dffTrace = (sig465 - fitted405) ./ fitted405;  % corrected ΔF/F


% -------------------------------------------------------------------------
% 5B) OPTIONAL: READ USV MAT (SHIFTED) -> EXTRACT CALL TIMES + TYPES
% -------------------------------------------------------------------------
% If provided, we overlay USV calls around Food/Drug events in a SIMPLE way:
%   - One row per call type (selected by user)
%   - Ticks show call times relative to reward (t=0)
%
% IMPORTANT: For correct alignment, this should be the *_SHIFTED.mat produced by
%            your USV_Timeline_shift pipeline step (same timebase as TTL/FP).
%
% We do NOT filter calls here. Filtering is controlled by UI toggles:
%   - type selection list (multi-select)
%   - accepted-only (or include rejected)

usv = struct();
usv.t_s      = [];
usv.type     = strings(0,1);
usv.accepted = true(0,1);

usvN       = 0;
usvMatUsed = "";
usvTypes   = strings(0,1);

if strlength(args.USVmat) > 0 && isfile(args.USVmat)
    usvMatUsed = args.USVmat;

    try
        usv = localLoadUSVCalls(usvMatUsed);

        % Clean NaNs/Infs (keep vectors aligned)
        usv.t_s = double(usv.t_s(:));
        good = isfinite(usv.t_s);

        usv.t_s = usv.t_s(good);
        usv.type = usv.type(good);
        usv.accepted = usv.accepted(good);

        usvN = numel(usv.t_s);

        % Stable list of call types for the filter UI
        usvTypes = unique(usv.type, 'stable');

    catch ME
        warning('TimesOfEventsV3: Could not read USV calls from MAT (%s). %s', usvMatUsed, ME.message);
        usv = struct('t_s',[],'type',strings(0,1),'accepted',true(0,1));
        usvN = 0;
        usvTypes = strings(0,1);
        usvMatUsed = "";
    end
end

% Display-only scaling (project convention)
%   - Keep computed corrected photometry values as raw fraction (ΔF/F).
%   - Only scale for plotting so values are readable (0.05 -> 5).
displayScale = 100;
%% =====================================================================
% 6) BUILD UI (standalone or embedded)
% =====================================================================

parent = args.Parent;   % store parent in a short name

ownsFigure = false;     % if we created the figure, we own it and can alert()
fig = [];               % handle to figure (needed for uialert)

% If no parent is provided, create a standalone window
if isempty(parent)
    fig = uifigure( ...
        'Color', 'white', ...
        'Name', 'Reward-aligned photometry (corrected ΔF/F)', ...
        'NumberTitle', 'off');
    root = fig;         % root container is the figure itself
    ownsFigure = true;

else
    % If parent is provided, create a panel that fills that parent
    root = uipanel(parent, ...
        'BorderType', 'none', ...
        'Units', 'normalized', ...
        'Position', [0 0 1 1]);
    fig = ancestor(root, 'figure');   % find the containing figure
end

% Layout:
% - Row 1: control bar (spans full width)
% - Row 2: content (plots on left, USV filters on right)
gl = uigridlayout(root, [2 2]);
gl.RowHeight    = {40, '1x'};
gl.ColumnWidth  = {'1x', 300};     % right column is the USV filter panel
gl.Padding      = [8 8 8 8];
gl.RowSpacing   = 6;
gl.ColumnSpacing = 10;

% Control row layout (7 columns)
ctrl = uigridlayout(gl, [1 7]);
ctrl.Layout.Row = 1;
ctrl.Layout.Column = [1 2];        % span across both columns
ctrl.ColumnWidth = {110, 60, 60, 70, 170, '1x', 300};
ctrl.RowHeight   = {28};
ctrl.Padding     = [0 0 0 0];
ctrl.ColumnSpacing = 8;

% --- Control widgets ---

% Label for window selector
lblWin = uilabel(ctrl, ...
    'Text', 'Display window:', ...
    'HorizontalAlignment', 'left');
lblWin.Layout.Row = 1;
lblWin.Layout.Column = 1;

% Buttons for window sizes
btn2 = uibutton(ctrl, 'push', 'Text', '±2 s');
btn2.Layout.Row = 1;
btn2.Layout.Column = 2;

btn5 = uibutton(ctrl, 'push', 'Text', '±5 s');
btn5.Layout.Row = 1;
btn5.Layout.Column = 3;

btn10 = uibutton(ctrl, 'push', 'Text', '±10 s');
btn10.Layout.Row = 1;
btn10.Layout.Column = 4;

% Checkbox: show/hide individual event traces (photometry only)
chk = uicheckbox(ctrl, ...
    'Text', 'Show individual events', ...
    'Value', logical(args.ShowIndividuals));
chk.Layout.Row = 1;
chk.Layout.Column = 5;

% Info label (right side): shows file/channel summary
[~, ttlBase]  = fileparts(args.TTLcsv);
[~, photoBase] = fileparts(args.PhotometryCsv);

infoText = sprintf('Channel: %s | Food=%d | Drug=%d | USV=%d | TTL: %s', ...
    sigName, numel(foodTimes), numel(drugTimes), usvN, ttlBase);
info = uilabel(ctrl, ...
    'Text', infoText, ...
    'HorizontalAlignment', 'right');
info.Layout.Row = 1;
info.Layout.Column = 7;

% Tooltip shows the full resolved paths (useful when label is truncated)
try
    info.Tooltip = sprintf('TTL: %s\nPhoto: %s\nUSV: %s', args.TTLcsv, args.PhotometryCsv, usvMatUsed);
catch
    % older MATLAB versions may not support Tooltip on uilabel
end

% ---- Content area (row 2) ----
% Left: plots (photometry on top, USV ticks below)
plotGL = uigridlayout(gl, [2 1]);
plotGL.Layout.Row = 2;
plotGL.Layout.Column = 1;
plotGL.RowHeight = {'3x', '1x'};
plotGL.ColumnWidth = {'1x'};
plotGL.Padding = [0 0 0 0];
plotGL.RowSpacing = 6;

% Top axes: photometry
ax = uiaxes(plotGL);
ax.Layout.Row = 1;
ax.Layout.Column = 1;
ax.Box = 'on';
grid(ax, 'on');

% Bottom axes: USV ticks (by type)
axUSV = uiaxes(plotGL);
axUSV.Layout.Row = 2;
axUSV.Layout.Column = 1;
axUSV.Box = 'on';
grid(axUSV, 'on');

% Right: USV type filter panel
pnlUSV = uipanel(gl, ...
    'Title', 'USV types', ...
    'FontWeight', 'bold');
pnlUSV.Layout.Row = 2;
pnlUSV.Layout.Column = 2;

pnlGL = uigridlayout(pnlUSV, [5 1]);
pnlGL.RowHeight = {18, 120, 320, 28, 28};  % label, type list, counts table, buttons, note
pnlGL.ColumnWidth = {'1x'};
pnlGL.Padding = [6 6 6 6];
pnlGL.RowSpacing = 6;

lblTypes = uilabel(pnlGL, 'Text', 'Toggle call types (multi-select):');
lblTypes.Layout.Row = 1;
lblTypes.Layout.Column = 1;

% List of types
if usvN > 0
    items = cellstr(usvTypes);
    % Default: select everything EXCEPT Noise (if present)
    def = usvTypes(~strcmpi(usvTypes, "Noise"));
    if isempty(def)
        def = usvTypes;
    end
    defValue = cellstr(def);
    enabledState = 'on';
else
    items = {'(no USV MAT loaded)'};
    defValue = {'(no USV MAT loaded)'};
    enabledState = 'off';
end

lbTypes = uilistbox(pnlGL, ...
    'Items', items, ...
    'Value', defValue, ...
    'Multiselect', 'on');
lbTypes.Layout.Row = 2;
lbTypes.Layout.Column = 1;
lbTypes.Enable = enabledState;


% Table: per-type counts (updates with window size)
% Columns are split by condition AND time relative to reward:
%   - Food<0 : calls before reward (t<0) around Food events
%   - Food>0 : calls after reward (t>=0) around Food events
%   - Drug<0 / Drug>0 : same for Drug events
tblCounts = uitable(pnlGL);
tblCounts.Layout.Row = 3;
tblCounts.Layout.Column = 1;
tblCounts.Enable = enabledState;
tblCounts.ColumnName = {'Type','Food<0','Food>0','Drug<0','Drug>0'};
tblCounts.ColumnEditable = [false false false false false];
tblCounts.RowName = {};
tblCounts.Data = cell(0, 5);
tblCounts.FontSize = 10;  % helps fit up to ~16 types without scrolling

tblCounts.ColumnWidth = {110, 45, 45, 45, 45};


% Buttons: All / None
btnRow = uigridlayout(pnlGL, [1 2]);
btnRow.Layout.Row = 4;
btnRow.Layout.Column = 1;
btnRow.ColumnWidth = {'1x', '1x'};
btnRow.RowHeight = {28};
btnRow.Padding = [0 0 0 0];
btnRow.ColumnSpacing = 6;

btnAllTypes = uibutton(btnRow, 'push', 'Text', 'All');
btnAllTypes.Layout.Row = 1;
btnAllTypes.Layout.Column = 1;
btnAllTypes.Enable = enabledState;

btnNoneTypes = uibutton(btnRow, 'push', 'Text', 'None');
btnNoneTypes.Layout.Row = 1;
btnNoneTypes.Layout.Column = 2;
btnNoneTypes.Enable = enabledState;


% Small note / count label (updated in updatePlot)
lblUSVNote = uilabel(pnlGL, ...
    'Text', '', ...
    'HorizontalAlignment', 'left');
lblUSVNote.Layout.Row = 5;
lblUSVNote.Layout.Column = 1;

%% =====================================================================
% 7) PLOT UPDATE LOGIC (callbacks + update function)
% =====================================================================

% Current window value (seconds)
currentWin_s = args.DefaultWin_s;

% Keep last computed data struct
latestData = struct();

% We store win values in UserData so the callback is simple
btn2.UserData  = struct('win_s', 2);
btn5.UserData  = struct('win_s', 5);
btn10.UserData = struct('win_s', 10);

% Assign ONE callback per type (beginner style)
btn2.ButtonPushedFcn  = @onWinButton;
btn5.ButtonPushedFcn  = @onWinButton;
btn10.ButtonPushedFcn = @onWinButton;

chk.ValueChangedFcn   = @onCheckboxChanged;

% USV filter callbacks
lbTypes.ValueChangedFcn   = @onUSVFilterChanged;
btnAllTypes.ButtonPushedFcn = @onUSVAllTypes;
btnNoneTypes.ButtonPushedFcn = @onUSVNoneTypes;

% First plot as soon as the UI is created
latestData = updatePlot(currentWin_s);


%% =====================================================================
% 8) OUTPUT STRUCT (so the app can call Refresh and access handles)
% =====================================================================
out = struct();
out.Root   = root;                 % root container created by this function
out.UIAxes = ax;                   % photometry axes
out.UIAxesUSV = axUSV;             % USV tick axes

% Control handles (useful for external scripts / app integration)
out.Controls = struct();
out.Controls.btn2 = btn2;
out.Controls.btn5 = btn5;
out.Controls.btn10 = btn10;
out.Controls.chkIndividuals = chk;
out.Controls.lblInfo = info;
out.Controls.lbUSVTypes = lbTypes;
out.Controls.tblUSVCounts = tblCounts;
out.Controls.btnAllTypes = btnAllTypes;
out.Controls.btnNoneTypes = btnNoneTypes;
out.Controls.lblUSVNote = lblUSVNote;
% Store parsed inputs used to build the UI
out.Inputs = args;
out.Inputs.ChannelUsed = sigName;  % record which channel was actually used (G0 or G1)

% Store computed data from the most recent plot
out.Data = latestData;

% Provide a function handle for refreshing the plot
% Example usage: out.Refresh(5)  -> uses ±5 seconds
out.Refresh = @safeUpdate;


%% =====================================================================
% 9) CALLBACKS (nested so they can access variables like ax, dt, etc.)
% =====================================================================
    function onWinButton(src, ~)
        % A window-size button was pressed.
        % win value is stored in src.UserData.win_s
        w = src.UserData.win_s;
        safeUpdate(w);
    end

    function onCheckboxChanged(~, ~)
        % Checkbox changed: redraw with the current window.
        safeUpdate(currentWin_s);
    end

function onUSVFilterChanged(~, ~)
    % USV type selection changed.
    safeUpdate(currentWin_s);
end

function onUSVAllTypes(~, ~)
    % Select all available USV types.
    if strcmpi(lbTypes.Enable, 'on')
        lbTypes.Value = lbTypes.Items;
    end
    safeUpdate(currentWin_s);
end

function onUSVNoneTypes(~, ~)
    % Deselect all types (shows no USV ticks).
    if strcmpi(lbTypes.Enable, 'on')
        try
            lbTypes.Value = {};
        catch
            % Some MATLAB versions may not allow empty selection.
            % In that case we keep the current selection.
        end
    end
    safeUpdate(currentWin_s);
end

    function dataOut = safeUpdate(win_s)
        % Wrap updatePlot in try/catch to avoid crashing the whole app tab.
        try
            dataOut = updatePlot(win_s);     % recompute and redraw
            latestData = dataOut;            % keep as latest
            out.Data = latestData; %#ok<NASGU>
        catch ME
            % If we own the figure, show alert. Otherwise, just warn.
            if ownsFigure && ~isempty(fig) && isvalid(fig)
                uialert(fig, ME.message, 'TimesOfEventsV3 error');
            else
                warning('TimesOfEventsV3: %s', ME.message);
            end
            dataOut = struct();
        end
    end

    function dataOut = updatePlot(win_s)
        % This function:
        %   - collects windows around events
        %   - baseline-corrects them
        %   - computes mean±std
        %   - plots results and AUC text

        % Store the current window choice (so checkbox redraw uses it)
        currentWin_s = win_s;

        % Clear axes and reset hold/grid each update
        % Clear both axes each update
cla(ax, 'reset');
hold(ax, 'on');
grid(ax, 'on');
ax.Box = 'on';

cla(axUSV, 'reset');
hold(axUSV, 'on');
grid(axUSV, 'on');
axUSV.Box = 'on';

        % Convert seconds window -> samples (pre + post)
        % Example: win_s=5, dt=0.1 -> preN=50 samples
        preN  = max(1, round(win_s / dt));
        postN = preN;
        winLen = preN + postN + 1;

        % Build time axis around the event (0 = reward)
        tAxis = (-preN : postN)' * dt;

        % Read checkbox state (show individual traces or not)
        showInd = logical(chk.Value);

        % Extract event windows for Food and Drug
        foodEvents = localCollectWindows(pairTime, dffTrace, foodTimes, preN, postN, args.BaselineMode);
        drugEvents = localCollectWindows(pairTime, dffTrace, drugTimes, preN, postN, args.BaselineMode);

        mainTitle = 'Food vs Drug reward — corrected photometry response';

        % If there are no events, just draw empty axes with labels
        if isempty(foodEvents) && isempty(drugEvents)

            title(ax, {mainTitle; photoBase}, 'FontWeight', 'bold');
            xlabel(ax, 'Time relative to reward (s)');
            ylabel(ax, 'Z-Score');
            xlim(ax, [-win_s win_s]);

% Also update the USV axis so the user understands why it is empty
xlabel(axUSV, 'Time relative to reward (s)');
xlim(axUSV, [-win_s win_s]);
xline(axUSV, 0, '--k', 'LineWidth', 1, 'HandleVisibility', 'off');
title(axUSV, 'USV calls (no TTL events found)', 'FontWeight', 'bold');
axUSV.YTick = [];
axUSV.YTickLabel = {};
ylabel(axUSV, '');
lblUSVNote.Text = 'No TTL events found (Food/Drug).';
try
    tblCounts.Data = cell(0, 5);
catch
end
ylim(axUSV, [0 1]);

            dataOut = struct();
            dataOut.tAxis = tAxis;
            dataOut.foodEvents = foodEvents;
            dataOut.drugEvents = drugEvents;
            dataOut.dt = dt;
            dataOut.win_s = win_s;
            return;
        end

        % Compute mean and STD across events
        [foodMean, foodSTD] = localMeanSTD(foodEvents, winLen);
        [drugMean, drugSTD] = localMeanSTD(drugEvents, winLen);

        % Optional: plot individual event traces (thin lines)
        if showInd
            if ~isempty(foodEvents)
                plot(ax, tAxis, foodEvents' * displayScale, ...
                    'Color', [0.60 0.85 0.60], ...
                    'LineWidth', 0.5, ...
                    'HandleVisibility', 'off');
            end

            if ~isempty(drugEvents)
                plot(ax, tAxis, drugEvents' * displayScale, ...
                    'Color', [0.90 0.60 0.60], ...
                    'LineWidth', 0.5, ...
                    'HandleVisibility', 'off');
            end
        end

        % Plot Food mean ± STD
        if ~isempty(foodEvents)
            localShade(ax, tAxis, (foodMean - foodSTD) * displayScale, (foodMean + foodSTD) * displayScale, [0 0.7 0], 0.18);
            plot(ax, tAxis, foodMean * displayScale, ...
                'Color', [0 0.55 0], ...
                'LineWidth', 2, ...
                'DisplayName', sprintf('Food reward mean (n=%d)', size(foodEvents, 1)));
        end

        % Plot Drug mean ± STD
        if ~isempty(drugEvents)
            localShade(ax, tAxis, (drugMean - drugSTD) * displayScale, (drugMean + drugSTD) * displayScale, [1 0 0], 0.18);
            plot(ax, tAxis, drugMean * displayScale, ...
                'Color', [0.80 0 0], ...
                'LineWidth', 2, ...
                'DisplayName', sprintf('Drug reward mean (n=%d)', size(drugEvents, 1)));
        end

        % Draw vertical line at the reward time (t=0)
        xline(ax, 0, '--k', 'LineWidth', 1, 'HandleVisibility', 'off');
% ---------- USV tick plot (simple: calls around reward) ----------
% Goal:
%   Show WHERE calls occur (relative to reward), with ONE row per call type.
%
% How to read:
%   - X: time relative to reward (seconds)
%   - Rows: call types (row order matches the listbox order)
%   - Green: calls around Food rewards
%   - Red:   calls around Drug rewards
%
% Notes:
%   - This is a peri-event view: calls are plotted by their time relative to each reward.
%   - In your lever protocol, rewards are sufficiently spaced that a call will not fall
%     into multiple reward windows for the same plot.

xlabel(axUSV, 'Time relative to reward (s)');
xlim(axUSV, [-win_s win_s]);
xline(axUSV, 0, '--k', 'LineWidth', 1, 'HandleVisibility', 'off');

% Reset y-axis labels (we rely on the table for type names)
axUSV.YTick = [];
axUSV.YTickLabel = {};
ylabel(axUSV, '');

% Default: clear counts table too
try
    tblCounts.Data = cell(0, 5);
catch
    % ignore
end

if usvN == 0 || strcmpi(lbTypes.Enable, 'off')
    title(axUSV, 'USV calls (no USV MAT loaded)', 'FontWeight', 'bold');
    lblUSVNote.Text = 'No USV MAT loaded.';
    ylim(axUSV, [0 1]);

else
    % Keep selection order STABLE (based on listbox Items order)
    allOrder = string(lbTypes.Items(:));
    selRaw   = string(lbTypes.Value(:));
    selRaw(selRaw == "(no USV MAT loaded)") = [];

    % Keep only items that are actually in the list, in list order
    selectedTypes = intersect(allOrder, selRaw, 'stable');

    if isempty(selectedTypes)
        title(axUSV, 'USV calls (no types selected)', 'FontWeight', 'bold');
        lblUSVNote.Text = 'No types selected.';
        ylim(axUSV, [0 1]);

    else
        % Filter calls by selected type(s) and keep ONLY accepted calls
        keep = ismember(usv.type, selectedTypes);
        keep = keep & usv.accepted;

        tCall    = usv.t_s(keep);
        typeCall = usv.type(keep);
        % Collect relative call times around Food and Drug events
        % (Per-event: standard peri-event view; duplicates would only occur if rewards were
        %  closer than the window, which your protocol avoids.)
        [relFood, typeFood] = localCollectRelUSV(tCall, typeCall, foodTimes, win_s);
        [relDrug, typeDrug] = localCollectRelUSV(tCall, typeCall, drugTimes, win_s);

        % Plot per type row (Food slightly above, Drug slightly below)
        nT = numel(selectedTypes);
        yRows = 1:nT;

        for it = 1:nT
            thisType = selectedTypes(it);

            yF = yRows(it) + 0.15;
            yD = yRows(it) - 0.15;

            idxF = strcmpi(typeFood, thisType);
            tf = relFood(idxF);
            if ~isempty(tf)
                plot(axUSV, tf, yF * ones(size(tf)), '|', ...
                    'LineStyle', 'none', ...
                    'Color', [0 0.55 0], ...
                    'MarkerSize', 14, ...
                    'LineWidth', 2.5);
            end

            idxD = strcmpi(typeDrug, thisType);
            td = relDrug(idxD);
            if ~isempty(td)
                plot(axUSV, td, yD * ones(size(td)), '|', ...
                    'LineStyle', 'none', ...
                    'Color', [0.80 0 0], ...
                    'MarkerSize', 14, ...
                    'LineWidth', 2.5);
            end
        end

        axUSV.YTick = yRows;
        axUSV.YTickLabel = cellstr(selectedTypes);   % show labels on left
        axUSV.YLim = [0, nT + 1];
        ylabel(axUSV, 'USV call type');
        title(axUSV, sprintf('USV calls in ±%gs (green=Food, red=Drug)', win_s), 'FontWeight', 'bold');

        % --------- Build per-type BEFORE/AFTER counts table ---------
        % Before:  t < 0
        % After:   t >= 0
        tableData = cell(nT, 5);
        for it = 1:nT
            thisType = selectedTypes(it);

            fPre  = sum(strcmpi(typeFood, thisType) & (relFood < 0));
            fPost = sum(strcmpi(typeFood, thisType) & (relFood >= 0));

            dPre  = sum(strcmpi(typeDrug, thisType) & (relDrug < 0));
            dPost = sum(strcmpi(typeDrug, thisType) & (relDrug >= 0));

            tableData{it,1} = char(thisType);
            tableData{it,2} = fPre;
            tableData{it,3} = fPost;
            tableData{it,4} = dPre;
            tableData{it,5} = dPost;
        end

        try
            tblCounts.Data = tableData;
        catch
            % ignore (older MATLAB edge cases)
        end
        % Status note
        lblUSVNote.Text = sprintf('Calls used: %d | Ticks: Food=%d, Drug=%d', numel(tCall), numel(relFood), numel(relDrug));
    end
end
% Labels and legend
        title(ax, {mainTitle; photoBase}, 'FontWeight', 'bold');
        xlabel(ax, 'Time relative to reward (s)');
        ylabel(ax, 'Z-Score');
        legend(ax, 'Location', 'best');
        xlim(ax, [-win_s win_s]);

        % ---------- AUC+ stats ----------
        % Compute AUC (only positive values) from 0 to +win_s
        postMask = (tAxis >= 0);   % logical mask for post-reward region

        [foodAUCm, foodAUCstd, nFood] = localAUCposMeanSTD(foodEvents, tAxis, postMask);
        [drugAUCm, drugAUCstd, nDrug] = localAUCposMeanSTD(drugEvents, tAxis, postMask);

        % Remove old AUC text (avoid stacking)
        delete(findall(ax, 'Type', 'text', 'Tag', 'AUCText'));

        % Build AUC text strings
        hdr = sprintf('AUC+ (0 → +%gs) above baseline (mean ± STD)', win_s);

        if nFood > 0
            foodLine = sprintf('Food:  %.4g ± %.4g  (n=%d)', foodAUCm * displayScale, foodAUCstd * displayScale, nFood);
        else
            foodLine = 'Food:  n=0';
        end

        if nDrug > 0
            drugLine = sprintf('Drug:  %.4g ± %.4g  (n=%d)', drugAUCm * displayScale, drugAUCstd * displayScale, nDrug);
        else
            drugLine = 'Drug:  n=0';
        end

        if nFood > 0 && nDrug > 0
            d = foodAUCm - drugAUCm;
            deltaLine = sprintf('\x0394(Food-Drug): %.4g', d * displayScale);
        else
            deltaLine = '\x0394(Food-Drug): n/a';
        end

        txt = sprintf('%s\n%s\n%s\n%s', hdr, foodLine, drugLine, deltaLine);

        % Draw text box in top-left inside axes
        text(ax, 0.02, 0.98, txt, ...
            'Units', 'normalized', ...
            'VerticalAlignment', 'top', ...
            'HorizontalAlignment', 'left', ...
            'BackgroundColor', 'w', ...
            'EdgeColor', [0.7 0.7 0.7], ...
            'Margin', 6, ...
            'FontSize', 10, ...
            'Tag', 'AUCText');

        % Return a data struct (useful for debugging or external export)
        dataOut = struct();
        dataOut.tAxis = tAxis;
        dataOut.foodEvents = foodEvents;
        dataOut.drugEvents = drugEvents;
        dataOut.foodMean = foodMean;
        dataOut.foodSTD  = foodSTD;
        dataOut.drugMean = drugMean;
        dataOut.drugSTD  = drugSTD;
        dataOut.foodAUCm   = foodAUCm;
        dataOut.foodAUCstd = foodAUCstd;
        dataOut.drugAUCm   = drugAUCm;
        dataOut.drugAUCstd = drugAUCstd;
        dataOut.nFood = nFood;
        dataOut.nDrug = nDrug;
        dataOut.dt = dt;
        dataOut.win_s = win_s;
    end

end


%% =====================================================================
% LOCAL FUNCTIONS (kept at bottom; each is small and single-purpose)
% =====================================================================

function x = localPickNumericTimeColumn(T)
% Pick the most likely TTL timestamp column from the TTLBox CSV table.

vars = T.Properties.VariableNames;

% Prefer Var4 (common TTLBox export)
if any(strcmpi(vars, 'Var4'))
    x = double(T.(localResolveVarNameCI(T, 'Var4')));
    return;
end

% Otherwise: pick the numeric column with the most finite values
bestVar = '';
bestCount = -inf;

for i = 1:numel(vars)
    v = T.(vars{i});
    if isnumeric(v)
        c = sum(isfinite(double(v)));
        if c > bestCount
            bestCount = c;
            bestVar = vars{i};
        end
    end
end

if isempty(bestVar)
    error('TTLBox: could not find a numeric time column (Var4 not present, no numeric columns).');
end

x = double(T.(bestVar));
end

function [starts, widths_ms] = localExtractPulsesBestPairing(ttlTime)
% Extract pulse START times and widths from a vector of TTL timestamps.
%
% TTLBox often writes times in pairs:
%   start1,end1,start2,end2,...
% But occasionally the file may have an extra leading time, or a missing time,
% so we test two pairing patterns and pick the better one.

n = numel(ttlTime);

% ---------------- Pairing A ----------------
% (1,2), (3,4), (5,6), ...
nA = floor(n/2) * 2;          % largest even number <= n
tA = ttlTime(1:nA);           % only use full pairs

startsA = tA(1:2:end-1);      % 1,3,5,...
endsA   = tA(2:2:end);        % 2,4,6,...

wA = (endsA - startsA) * 1000; % widths in ms

% ---------------- Pairing B ----------------
% Shift by one: (2,3), (4,5), ...
if n >= 5
    % compute a safe length for shifted pairing
    nB = floor((n-1)/2)*2 + 1;   % odd length so indices align
    tB = ttlTime(1:nB);

    startsB = tB(2:2:end-1);
    endsB   = tB(3:2:end);

    wB = (endsB - startsB) * 1000;
else
    startsB = [];
    wB = [];
end

% Score each pairing by counting "reasonable" widths
% We consider 1 ms to 500 ms as plausible TTL pulses here.
scoreA = sum(wA > 1 & wA < 500);
scoreB = sum(wB > 1 & wB < 500);

% Choose best pairing
if scoreB > scoreA
    starts = startsB;
    widths_ms = wB;
else
    starts = startsA;
    widths_ms = wA;
end
end

function tf = localWidthMatches(widths_ms, target_ms, tolPct)
% Return logical vector: widths_ms matches the target width within tolerance.

tf = false(size(widths_ms));

% Convert tolerance percent -> fraction
tol = tolPct / 100;

% Support scalar target or vector of targets
targets = target_ms(:);

for k = 1:numel(targets)
    w = targets(k);
    tf = tf | (abs(widths_ms - w) <= tol * w);
end
end

function v = localGetVarCI(T, candidates)
% Get a table variable by trying multiple candidate names (case-insensitive).

vars = T.Properties.VariableNames;
idx = [];

for i = 1:numel(candidates)
    j = find(strcmpi(vars, candidates{i}), 1);
    if ~isempty(j)
        idx = j;
        break;
    end
end

if isempty(idx)
    error('Missing required column. Tried: %s', strjoin(candidates, ', '));
end

v = T.(vars{idx});
end

function name = localResolveVarNameCI(T, candidate)
% Resolve a variable name case-insensitively to the exact stored name.

vars = T.Properties.VariableNames;
j = find(strcmpi(vars, candidate), 1);

if isempty(j)
    error('Column not found: %s', candidate);
end

name = vars{j};
end

function [pairTime, sig465, sig405] = localBuildLedPairs_465_405(t, led, sig)
% Build adjacent LED pairs from raw photometry streams.
%
% Common encoding:
%   - LedState 2 and 1 alternate
% We accept either adjacency direction:
%   A) 2 then 1 -> treat as (465,405)
%   B) 1 then 2 -> treat as (405,465)
%
% We choose whichever adjacency occurs more often.

idxA = find(led(1:end-1) == 2 & led(2:end) == 1); % pattern: 2->1
idxB = find(led(1:end-1) == 1 & led(2:end) == 2); % pattern: 1->2

if numel(idxB) > numel(idxA)
    % Pattern B is more common: (405 at i), (465 at i+1)
    i = idxB;
    sig405 = sig(i);
    sig465 = sig(i+1);
    pairTime = t(i+1);    % use time of 465 sample (more common convention)
else
    % Pattern A is more common: (465 at i), (405 at i+1)
    i = idxA;
    sig465 = sig(i);
    sig405 = sig(i+1);
    pairTime = t(i);      % use time of 465 sample
end

if isempty(pairTime)
    error('No adjacent LedState pairs found (need 2/1 or 1/2 adjacency).');
end
end

function events = localCollectWindows(tBase, trace, eventTimes, preN, postN, baselineMode)
% Extract windows of length (preN+postN+1) around each event time.
% Each extracted window is baseline-corrected based on baselineMode.

% If there are no events, return an empty 0-by-winLen matrix
if isempty(eventTimes)
    events = zeros(0, preN + postN + 1);
    return;
end

N = numel(tBase);
winLen = preN + postN + 1;

% Convert event times to nearest sample indices on the paired time axis
idx = interp1(tBase, (1:N)', eventTimes(:), 'nearest', 'extrap');
idx = round(idx);
idx = max(1, min(N, idx));

% Collect windows one-by-one (explicit loop, easier to debug)
events = [];

for k = 1:numel(idx)

    % Center index for this event
    i0 = idx(k);

    % Window start/end indices
    i1 = i0 - preN;
    i2 = i0 + postN;

    % Skip if window would go out of bounds
    if i1 < 1 || i2 > N
        continue;
    end

    % Extract segment
    seg = trace(i1:i2);

    % Choose baseline value
    mode = string(baselineMode);
    if mode == "mean_pre"
        base = mean(seg(1:preN), 'omitnan');
    elseif mode == "first_sample"
        base = seg(1);
    else
        % Default
        base = mean(seg(1:preN), 'omitnan');
    end

    % Baseline-correct
    seg = seg - base;

    % Append as a row (1 x winLen)
    events = [events; seg(:)']; %#ok<AGROW>
end

% Sanity check: each window should have expected length
if ~isempty(events) && size(events, 2) ~= winLen
    error('Window extraction bug: unexpected window length.');
end
end

function [m, s] = localMeanSTD(events, winLen)
% Compute mean and STD across events (rows), returning column vectors.

if isempty(events)
    m = nan(winLen, 1);
    s = nan(winLen, 1);
    return;
end

m = mean(events, 1, 'omitnan')';
s = std(events, 0, 1, 'omitnan')';
end

function localShade(ax, x, y1, y2, rgb, alphaVal)
% Draw a shaded region between y1 and y2.

patch(ax, [x; flipud(x)], [y1(:); flipud(y2(:))], rgb, ...
    'FaceAlpha', alphaVal, ...
    'EdgeColor', 'none', ...
    'HandleVisibility', 'off');
end

function [aucMean, aucSTD, n] = localAUCposMeanSTD(events, tAxis, mask)
% Compute AUC of positive part only (yPos=max(y,0)) across events.

if isempty(events)
    aucMean = NaN;
    aucSTD  = NaN;
    n = 0;
    return;
end

% Time values for integration
x = tAxis(mask)';

% Extract post-mask region
y = events(:, mask);

% Positive part only
yPos = max(y, 0);

% Integrate each event row -> one AUC value per event
aucVec = trapz(x, yPos, 2);

n = numel(aucVec);
aucMean = mean(aucVec, 'omitnan');
aucSTD  = std(aucVec, 0, 'omitnan');
end


function [allRel_s, allType] = localCollectRelUSV(callTimes_s, callTypes, eventTimes_s, win_s)
% Collect USV call times relative to a list of event times.
%
% Inputs
%   callTimes_s   : vector of USV call start times (seconds)
%   callTypes     : vector of call type labels (same length as callTimes_s)
%   eventTimes_s  : vector of event times (seconds)
%   win_s         : peri-event window (+/- seconds)
%
% Outputs
%   allRel_s : pooled relative call times (seconds)
%   allType  : pooled call type labels (same length as allRel_s)

allRel_s = [];
allType  = strings(0,1);

if isempty(callTimes_s) || isempty(eventTimes_s)
    return;
end

callTimes_s = double(callTimes_s(:));
callTypes   = string(callTypes(:));

for k = 1:numel(eventTimes_s)
    t0 = eventTimes_s(k);

    % Relative times for all calls
    rel = callTimes_s - t0;

    % Keep calls inside the window
    keep = (rel >= -win_s) & (rel <= win_s);

    if any(keep)
        allRel_s = [allRel_s; rel(keep)]; %#ok<AGROW>
        allType  = [allType;  callTypes(keep)]; %#ok<AGROW>
    end
end
end


function usv = localLoadUSVCalls(usvMatPath)
% Load DeepSqueak MAT and return:
%   - usv.t_s       : call START times (seconds)
%   - usv.type      : call type label per call
%   - usv.accepted  : logical accepted flag per call
%
% This tries to be robust to common DeepSqueak formats:
%   - Calls table with variable "Box" (cell Nx1 or numeric Nx4)
%   - Calls table with "StartTime"/"BeginTime" columns
%   - Calls table with "Type"/"Label" type labels
%   - Calls table with "Accept"/"Accepted" acceptance flags
%
% No filtering is done here. Filtering is handled by the UI.

S = load(usvMatPath);

% ---------------------------------------------------------------------
% 1) Find a Calls table
% ---------------------------------------------------------------------
Calls = [];

if isfield(S, 'Calls')
    Calls = S.Calls;
else
    % Fallback: find the first table that looks like Calls
    f = fieldnames(S);
    for i = 1:numel(f)
        v = S.(f{i});
        if istable(v)
            Calls = v;
            break;
        end
    end
end

if isempty(Calls)
    error('No Calls table found in USV MAT.');
end

if ~istable(Calls)
    error('USV MAT: Calls is not a table (unexpected format).');
end

n = height(Calls);

% ---------------------------------------------------------------------
% 2) Extract acceptance (default: all accepted)
% ---------------------------------------------------------------------
accepted = true(n, 1);

vars = Calls.Properties.VariableNames;

accVar = '';
if any(strcmpi(vars, 'Accept'))
    accVar = vars{strcmpi(vars, 'Accept')};
elseif any(strcmpi(vars, 'Accepted'))
    accVar = vars{strcmpi(vars, 'Accepted')};
elseif any(strcmpi(vars, 'isAccepted'))
    accVar = vars{strcmpi(vars, 'isAccepted')};
end

if ~isempty(accVar)
    try
        a = Calls.(accVar);

        if islogical(a)
            accepted = a(:);
        elseif isnumeric(a)
            accepted = a(:) ~= 0;
        else
            % If the column is stored as text/cell, try a safe conversion
            accepted = logical(double(a(:)));
        end
    catch
        % Keep default (all true) if conversion fails
        accepted = true(n, 1);
    end
end

% ---------------------------------------------------------------------
% 3) Extract type label (default: "USV")
% ---------------------------------------------------------------------
type = repmat("USV", n, 1);

typeVar = '';
candidates = {'Type','Label','CallType','Category'};
for i = 1:numel(candidates)
    if any(strcmpi(vars, candidates{i}))
        typeVar = vars{strcmpi(vars, candidates{i})};
        break;
    end
end

if ~isempty(typeVar)
    try
        type = string(Calls.(typeVar));
    catch
        type = repmat("USV", n, 1);
    end
end

% ---------------------------------------------------------------------
% 4) Extract call START time (seconds)
% ---------------------------------------------------------------------
tStart_s = nan(n, 1);

% Prefer Box column (DeepSqueak typical)
if any(strcmpi(vars, 'Box'))
    boxName = vars{strcmpi(vars, 'Box')};
    box = Calls.(boxName);

    if iscell(box)
        for i = 1:numel(box)
            b = box{i};
            if isnumeric(b) && ~isempty(b)
                tStart_s(i) = b(1);
            end
        end

    elseif isnumeric(box)
        if size(box, 2) >= 1
            tStart_s = box(:, 1);
        end
    end
end

% Fallback: StartTime/BeginTime-like columns
if all(isnan(tStart_s))
    timeCandidates = {'StartTime','BeginTime','Start','Begin','TimeStart','tStart','Start_s'};
    for i = 1:numel(timeCandidates)
        if any(strcmpi(vars, timeCandidates{i}))
            nm = vars{strcmpi(vars, timeCandidates{i})};
            try
                tStart_s = double(Calls.(nm));
            catch
                % ignore, try next
            end
            break;
        end
    end
end

if all(isnan(tStart_s))
    error('Could not extract USV call start times (no Box or StartTime-like columns).');
end

% ---------------------------------------------------------------------
% 5) Return struct
% ---------------------------------------------------------------------
usv = struct();
usv.t_s = tStart_s(:);
usv.type = string(type(:));
usv.accepted = logical(accepted(:));
end
