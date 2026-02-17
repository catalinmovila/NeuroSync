function outXlsx = FP_TTL_USV_Experiment_overview(varargin)
% FP_TTL_USV_Experiment_overview  (PASS 2: extra-declustered + heavy comments)
% -------------------------------------------------------------------------
% GOAL
%   Create ONE Excel overview file for ONE experiment, using your fixed layout.
%
% LAYOUT (rows/columns)
%   Columns (6):
%     Col A: row labels
%     Col B: Full
%     Col C: Segment 1
%     Col D: Segment 2
%     Col E: Segment 3
%     Col F: Rate per 5 minutes (based on Full / duration)
%
%   Rows:
%     1) Food Rewards
%     2) Drug Rewards
%     3) Peak count
%     4) Peak Average
%     5..(n-2)) USV categories (your fixed list) + a catch-all "USV" row
%     last) Total USVs
%
% IMPORTANT BEHAVIOR RULE
%   - We NEVER silently drop USV calls.
%   - If a call label does not match your template list,
%     it is counted under the "USV" catch-all row.
%
% TIME / SEGMENT RULES
%   - FP time is shifted so the first FP sample is t=0 seconds.
%   - The FP recording is split into 3 equal segments by total duration.
%   - TTL times (TTLBox CSV) can be shifted by TTLShiftSec (optional).
%   - USV times (DeepSqueak MAT) can be mapped using SyncMappingXlsx (optional)
%     and then shifted by USVShiftSec (optional).
%
% INPUTS (Name/Value pairs)
%   'FPmat'            : corrected FP MAT (REQUIRED)
%   'TTLcsv'           : TTLBox CSV (optional)
%   'USVmat'           : DeepSqueak Calls MAT (optional)
%   'OutXlsx'          : output Excel file path (REQUIRED)
%   'TTLShiftSec'      : shift TTL times to FP timeline (seconds)
%   'USVShiftSec'      : shift USV times to FP timeline (seconds)
%   'SyncMappingXlsx'  : mapping file (t_TTLBox = a*t_audio + b) (optional)
%   'TTLWav'           : TTL WAV file (optional; used only for Rate per 5 minutes)
%
% OUTPUT
%   outXlsx : path to the saved Excel file
%
% NOTE
%   This pass is a readability pass (more explicit variables + comments).
%   The deliverable layout and counting logic is kept the same.
% -------------------------------------------------------------------------


%% =====================================================================
% STEP 1) DEFAULTS
% =====================================================================
% These defaults are overwritten by Name/Value inputs or file dialogs.

fpMat   = "";   % corrected FP MAT file (required)
ttlCsv  = "";   % TTLBox CSV file (optional)
usvMat  = "";   % DeepSqueak calls MAT file (optional)
outXlsx = "";   % output Excel path (required)

TTLShiftSec = 0;     % shift TTL times into FP time base (seconds)
USVShiftSec = 0;     % shift USV times into FP time base (seconds)
syncXlsx    = "";    % *_SYNC_MAPPING.xlsx (optional)
ttlWav      = "";    % TTL WAV file (optional; used for rate calculation)


%% =====================================================================
% STEP 2) PARSE NAME/VALUE INPUTS (manual, beginner-style)
% =====================================================================
% Example:
%   FP_TTL_USV_Experiment_overview('FPmat','X.mat','TTLcsv','TTL.csv')

if ~isempty(varargin)

    % Must be pairs
    if mod(numel(varargin), 2) ~= 0
        error('Inputs must be name/value pairs. Example: FP_TTL_USV_Experiment_overview(''FPmat'',''file.mat'')');
    end

    % Walk through pairs: (1,2), (3,4), ...
    for i = 1:2:numel(varargin)

        % Read name/value
        nameIn = lower(string(varargin{i}));
        valIn  = varargin{i+1};

        % Apply each supported parameter explicitly
        if nameIn == "fpmat"
            fpMat = string(valIn);

        elseif nameIn == "ttlcsv"
            ttlCsv = string(valIn);

        elseif nameIn == "usvmat"
            usvMat = string(valIn);

        elseif nameIn == "outxlsx"
            outXlsx = string(valIn);

        elseif nameIn == "ttlshiftsec"
            TTLShiftSec = double(valIn);

        elseif nameIn == "usvshiftsec"
            USVShiftSec = double(valIn);

        elseif nameIn == "syncmappingxlsx"
            syncXlsx = string(valIn);

        elseif nameIn == "ttlwav"
            ttlWav = string(valIn);

        else
            error('Unknown parameter name: %s', nameIn);
        end
    end
end


%% =====================================================================
% STEP 3) PICK FILES IF MISSING (dialogs)
% =====================================================================

% 3.1 FP MAT (required)
if strlength(fpMat) == 0
    [f, p] = uigetfile({'*.mat','Corrected FP MAT (*.mat)'}, ...
        'Select corrected FP MAT (CorrectedSignal)');
    if isequal(f, 0)
        error('No FP MAT selected.');
    end
    fpMat = string(fullfile(p, f));
end

% 3.2 TTL CSV (optional)
if strlength(ttlCsv) == 0
    [f, p] = uigetfile({'*.csv','TTLBox CSV (*.csv)'; '*.*','All files'}, ...
        'Select TTLBox CSV (optional)');
    if ~isequal(f, 0)
        ttlCsv = string(fullfile(p, f));
    end
end

% 3.3 USV MAT (optional)
if strlength(usvMat) == 0
    [f, p] = uigetfile({'*.mat','DeepSqueak Calls MAT (*.mat)'; '*.*','All files'}, ...
        'Select USV Calls MAT (optional)');
    if ~isequal(f, 0)
        usvMat = string(fullfile(p, f));
    end
end

% 3.4 Output Excel (required)
if strlength(outXlsx) == 0
    [f, p] = uiputfile({'*.xlsx','Excel (*.xlsx)'}, ...
        'Save overview Excel as');
    if isequal(f, 0)
        error('No output Excel selected.');
    end
    outXlsx = string(fullfile(p, f));
end


%% =====================================================================
% STEP 4) LOAD CORRECTED FP SIGNAL (time + corrected trace)
% =====================================================================
[fpTime_s, fpSignal] = localLoadCorrectedFP(fpMat);

% Force FP time to start at 0 seconds
fpTime_s = fpTime_s - fpTime_s(1);

% FP end time (total duration)
Tend = fpTime_s(end);

% Decide which recording duration to use for the "Rate per 5 min" column.
% Priority:
%   1) TTL WAV duration (if provided and readable)
%   2) FP duration (Tend)
rateDurSec = Tend;  % default fallback
if strlength(ttlWav) > 0 && isfile(ttlWav)
    try
        ai = audioinfo(char(ttlWav));
        if isfield(ai, 'Duration') && ~isnan(ai.Duration) && ai.Duration > 0
            rateDurSec = ai.Duration;
        end
    catch
        % If audioinfo fails, we keep the FP fallback.
    end
end

% Convert to minutes and compute a multiplier.
% If FullCount is a count for the whole recording, then:
%   RatePer5Min = FullCount / (duration_min / 5) = FullCount * (5 / duration_min)
rateDurMin = rateDurSec / 60;
rateFactor5min = NaN;
if rateDurMin > 0
    rateFactor5min = 5 / rateDurMin;
end

% Define segment edges (3 equal thirds)
% edges = [0, 1/3, 2/3, end]
segEdges = [0, Tend/3, 2*Tend/3, Tend];


%% =====================================================================
% STEP 5) DEFINE FIXED EXCEL LAYOUT (headers + row labels)
% =====================================================================

% Column headers (Row 1 in Excel)
colHeaders = {'' 'Full' 'Segment 1' 'Segment 2' 'Segment 3' 'Rate per 5 minutes'};

% Row labels (Col A in Excel)
rowLabels = { ...
    'Food Rewards'
    'Drug Rewards'
    'Peak count'
    'Peak Average'
    'Complex'
    'Upward Ramp'
    'Downward Ramp'
    'Flat'
    'Short'
    'Split'
    'Step Up'
    'Step Down'
    'Multi-Step'
    'Trill'
    'Flat-trill'
    'Trill with Jumps'
    'Inverted U'
    'Composite'
    '22-KHz'
    'Unclear'
    'Miscellaneuous'
    'USV'
    'Total USVs'};

nRows = numel(rowLabels);

% The numeric matrix of results:
%   V(rowIndex, columnIndex)
% ColumnIndex mapping:
%   1 = Full, 2 = Segment1, 3 = Segment2, 4 = Segment3
V = zeros(nRows, 4);


%% =====================================================================
% STEP 6) TTL COUNTS (Food / Drug) FROM TTLBox CSV (optional)
% =====================================================================
% TTL coding rule in your project:
%   80 ms => Food
%   60 ms => Drug

if strlength(ttlCsv) > 0 && isfile(ttlCsv)

    % Parse TTLBox edges into pulses (start times + code_ms)
    ttl = localParseTTLBox(ttlCsv);

    % Shift TTL times into FP timeline (optional shift provided by user)
    ttlTimes_fp = ttl.times_s + TTLShiftSec;

    % Split Food and Drug timestamps
    foodTimes = ttlTimes_fp(ttl.code_ms == 80);
    drugTimes = ttlTimes_fp(ttl.code_ms == 60);

    % Count in Full + each segment
    for k = 1:4
        [aSeg, bSeg] = localSegmentBounds(k, segEdges);

        % Food row = 1
        V(1, k) = sum(foodTimes >= aSeg & foodTimes < bSeg);

        % Drug row = 2
        V(2, k) = sum(drugTimes >= aSeg & drugTimes < bSeg);
    end
end


%% =====================================================================
% STEP 7) PEAK COUNT + PEAK AVERAGE FROM FP TRACE
% =====================================================================
% We find peaks ONCE on the full FP trace, then count and average by segment.

tFull = fpTime_s;
zFull = fpSignal;

% ---------------- Display-only scaling for OUTPUTS ----------------
% Project rule:
%   - The corrected FP MAT values (fpSignal) stay UNCHANGED (raw fraction, ΔF/F).
%   - Only the Peak Average values written to the overview Excel are scaled x100
%     for readability (e.g., 0.05 -> 5).
peakDisplayScale = 100;


% Find all peaks (pks) and their time locations (locs)
[pks, locs] = localFindPeaks(tFull, zFull);

% Full peaks count and average
V(3, 1) = numel(pks);       % Peak count
V(4, 1) = meanOrZero(pks);  % Peak Average

% Segment peaks count and average
for s = 1:3

    % Segment bounds in FP time base
    aSeg = segEdges(s);
    bSeg = segEdges(s+1);

    % Decide which peaks fall into this segment
    % (include end point only for the last segment)
    if s < 3
        inSeg = (locs >= aSeg) & (locs < bSeg);
    else
        inSeg = (locs >= aSeg) & (locs <= bSeg);
    end

    % Write into V:
    % Row 3 = Peak count
    V(3, s+1) = sum(inSeg);

    % Row 4 = Peak Average
    V(4, s+1) = meanOrZero(pks(inSeg));
end

% Apply display scaling ONLY to Peak Average row (row 4).
% Peak count and all event/call counts remain unchanged.
V(4, :) = V(4, :) * peakDisplayScale;



%% =====================================================================
% STEP 8) USV COUNTS BY LABEL (optional)
% =====================================================================

% Row indices:
firstUSVrow = 5;   % 'Complex' is row 5
usvRow      = localFindRowIndex(rowLabels, 'USV');        % catch-all row
totalRow    = localFindRowIndex(rowLabels, 'Total USVs'); % total row

% Template labels we want to count (Complex..USV)
tmplLabels = rowLabels(firstUSVrow:usvRow);

% Normalize each template label into a comparable "key"
tmplNorm = cell(numel(tmplLabels), 1);
for r = 1:numel(tmplLabels)
    tmplNorm{r} = localNormLabel(tmplLabels{r});  % returns char
end

% Find which template index corresponds to the "USV" catch-all
usvIdx = numel(tmplLabels);  % fallback default = last one
for r = 1:numel(tmplLabels)
    if strcmp(tmplNorm{r}, 'usv')
        usvIdx = r;
        break;
    end
end

% Optional mapping: t_TTLBox = a*t_audio + b
useMap = false;
mapA = 1;   % drift
mapB = 0;   % offset

if strlength(syncXlsx) > 0 && isfile(syncXlsx)
    try
        [mapA, mapB] = localReadSyncMapping(syncXlsx);
        useMap = true;
    catch
        % If mapping cannot be read, we continue without mapping.
        useMap = false;
        mapA = 1;
        mapB = 0;
    end
end

% If USV MAT exists, load it and count calls
if strlength(usvMat) > 0 && isfile(usvMat)

    % Load call start times + labels from DeepSqueak MAT
    [callTimes_s, callLabels] = localLoadUSVCalls(usvMat);

    % Start with audio-time calls
    tUSV = callTimes_s;

    % Apply mapping into TTLBox time base, if available
    if useMap
        tUSV = mapA .* tUSV + mapB;
    end

    % Apply optional USV shift into FP timeline
    tUSV = tUSV + USVShiftSec;

    % Normalize every call label (student style loop)
    normLabs = cell(numel(callLabels), 1);
    for i = 1:numel(callLabels)

        lab = string(callLabels{i});
        lab = strtrim(lab);

        % If label is empty, treat as "USV"
        if strlength(lab) == 0
            lab = "USV";
        end

        % Normalize into a comparable key
        key = localNormLabel(lab);

        % If normalization returns empty for any reason, also treat as "USV"
        if isempty(key)
            key = 'usv';
        end

        normLabs{i} = key;  % store char
    end

    % Count per Full + Segment 1..3
    for k = 1:4

        % Segment bounds
        [aSeg, bSeg] = localSegmentBounds(k, segEdges);

        % Calls that fall into this segment
        inSeg = (tUSV >= aSeg) & (tUSV < bSeg);

        % Extract just the labels inside this segment
        labsSeg = normLabs(inSeg);

        % Count per template label
        counts = zeros(numel(tmplLabels), 1);

        for i = 1:numel(labsSeg)
            key = labsSeg{i};

            % Find which template index this key belongs to
            % If no match, returns usvIdx (catch-all)
            idx = localFindTemplateIndex(key, tmplNorm, usvIdx);

            % Increment count
            counts(idx) = counts(idx) + 1;
        end

        % Write template counts into V matrix
        for r = 1:numel(tmplLabels)
            rr = firstUSVrow + (r-1);
            V(rr, k) = counts(r);
        end

        % Total calls in this segment (no dropping)
        V(totalRow, k) = sum(inSeg);
    end
end


%% =====================================================================
% STEP 9) WRITE EXCEL FILE
% =====================================================================
% We build a cell matrix and write it with writecell.
% Shape = (header row + nRows) x (label col + 4 data cols + rate col) = (nRows+1) x 6

C = cell(nRows + 1, 6);

% 9.1 Header row
for c = 1:6
    C{1, c} = colHeaders{c};
end

% 9.2 Data rows
for r = 1:nRows

    % Row label in column A
    C{r+1, 1} = rowLabels{r};

    % Numeric values in columns B..E
    for k = 1:4
        C{r+1, 1+k} = V(r, k);
    end

    % Rate per 5 min (based on FULL column and full recording duration)
    % - Only meaningful for count rows.
    % - We leave Peak Average blank.
    rateVal = [];
    if ~isnan(rateFactor5min)
        if strcmp(rowLabels{r}, 'Peak Average')
            rateVal = [];
        else
            rateVal = V(r, 1) * rateFactor5min;
            % Round to 3 decimals (Excel readability)
            rateVal = round(rateVal * 1000) / 1000;
        end
    end
    C{r+1, 6} = rateVal;
end

% Write to Excel
writecell(C, outXlsx, 'Sheet', 'Sheet1', 'Range', 'A1');

% Print confirmation
fprintf('Saved overview Excel to: %s\n', outXlsx);

end


%% =====================================================================
% HELPER FUNCTIONS (kept beginner-readable and explicit)
% =====================================================================

function idx = localFindRowIndex(rowLabels, name)
% Find a row index in the rowLabels cell array by exact match.
idx = [];
for i = 1:numel(rowLabels)
    if strcmp(rowLabels{i}, name)
        idx = i;
        return;
    end
end
error('Row label not found: %s', name);
end

function idx = localFindTemplateIndex(key, tmplNorm, usvIdx)
% localFindTemplateIndex
%   - key      : normalized label (char)
%   - tmplNorm : cell array of normalized template labels (char)
% If no match is found, returns usvIdx (catch-all).

idx = usvIdx;  % default

for r = 1:numel(tmplNorm)
    if strcmp(key, tmplNorm{r})
        idx = r;
        return;
    end
end
end

function [t, z] = localLoadCorrectedFP(fpMat)
% Load corrected FP MAT and return:
%   t : time in seconds
%   z : corrected signal
%
% We support two possible MAT contents:
%   1) correctedSignalTable (preferred)
%   2) tablediffRelative    (legacy)

S = load(fpMat);

% Case 1) correctedSignalTable
if isfield(S, 'correctedSignalTable')
    T = S.correctedSignalTable;

    if istable(T)
        % Find Time column
        if any(strcmp(T.Properties.VariableNames, 'Time_s'))
            t = T.Time_s;
        else
            t = T{:, 1};
        end

        % Find Signal column
        if any(strcmp(T.Properties.VariableNames, 'CorrectedSignal'))
            z = T.CorrectedSignal;
        else
            z = T{:, 2};
        end
    else
        % If someone saved correctedSignalTable as a struct
        fn = fieldnames(T);

        % Time
        if any(strcmp(fn, 'Time_s'))
            t = T.Time_s;
        else
            t = T.(fn{1});
        end

        % Signal
        if any(strcmp(fn, 'CorrectedSignal'))
            z = T.CorrectedSignal;
        else
            if numel(fn) < 2
                error('correctedSignalTable struct does not contain enough fields to extract time/signal.');
            end
            z = T.(fn{2});
        end
    end

% Case 2) tablediffRelative
elseif isfield(S, 'tablediffRelative')
    T = S.tablediffRelative;

    if istable(T)
        % Typical legacy columns are Var1, Var2
        if any(strcmp(T.Properties.VariableNames, 'Var1'))
            t = T.Var1;
            z = T.Var2;
        else
            t = T{:, 1};
            z = T{:, 2};
        end
    else
        % numeric array fallback
        t = T(:, 1);
        z = T(:, 2);
    end

else
    error('FP MAT does not contain correctedSignalTable or tablediffRelative.');
end

% Ensure column vectors
if isrow(t); t = t'; end
if isrow(z); z = z'; end

% Ensure numeric
t = double(t);
z = double(z);
end

function ttl = localParseTTLBox(ttlCsv)
% Read TTLBox CSV robustly even if it has no header row.
% Extract LOW pulses (False -> next True) and classify them by pulse width.

T = readtable(ttlCsv, 'Delimiter', ',', 'ReadVariableNames', false);

% Expect at least 4 columns:
%   col3 = state (true/false)
%   col4 = time (seconds)
if width(T) < 4
    error('TTLBox CSV has unexpected number of columns.');
end

stateCol = T{:, 3};
timeCol  = T{:, 4};

stateStr = lower(strtrim(string(stateCol)));
time_s   = double(timeCol);

isFalse = (stateStr == "false");
isTrue  = (stateStr == "true");

N = numel(time_s);

starts    = [];
widths_ms = [];

% A LOW pulse is a row i where state is false AND the next row is true.
% Pulse width = (time(i+1) - time(i)) seconds -> convert to ms.
for i = 1:(N-1)
    if isFalse(i) && isTrue(i+1)
        w = (time_s(i+1) - time_s(i)) * 1000;  % ms
        if w > 0
            starts(end+1, 1)    = time_s(i); %#ok<AGROW>
            widths_ms(end+1, 1) = w;         %#ok<AGROW>
        end
    end
end

% If no pulses were found, return empty
if isempty(starts)
    ttl.times_s = zeros(0, 1);
    ttl.code_ms = zeros(0, 1);
    return;
end

% Shift starts so the first pulse is at t=0
starts = starts - starts(1);

% Classify widths to the nearest of {20,40,60,80} using a 5% tolerance
targets = [20 40 60 80];
codes   = zeros(size(widths_ms));
valid   = false(size(widths_ms));

for k = 1:numel(widths_ms)

    % Find closest target
    [d, idx] = min(abs(widths_ms(k) - targets));
    tgt = targets(idx);

    % Accept if within 5% of target
    if d <= 0.05 * tgt
        codes(k) = tgt;
        valid(k) = true;
    end
end

% Keep only valid pulses
starts = starts(valid);
codes  = codes(valid);

ttl.times_s = starts;
ttl.code_ms = codes;
end

function m = meanOrZero(x)
% meanOrZero: returns mean(x), but returns 0 if x is empty.
if isempty(x)
    m = 0;
else
    m = mean(x);
end
end

function [pks, locs] = localFindPeaks(t, z)
% localFindPeaks
% Uses the same controller-style peak detection logic you used before.
% Returns:
%   pks  : peak heights
%   locs : peak locations (time in seconds)

if numel(t) < 5
    pks = [];
    locs = [];
    return;
end

% Controller constants (kept consistent with your previous file)
upperBoundController = 1.0;
distanceBetweenPeaksController = 0.0075;

t = t(:);
zRaw = z(:);

% Compute mean + std
zmean = mean(zRaw, 'omitnan');
zstd  = std(zRaw, 'omitnan');

% Peak height threshold
upperBound = zmean + (upperBoundController * zstd);

% subtract mean before peak finding (as in your previous script)
zDet = zRaw - zmean;

% Minimum distance between peaks (scaled by recording duration)
dist = distanceBetweenPeaksController * (t(end) - t(1));
if ~isfinite(dist) || dist <= 0
    dist = 0;
end

% Run findpeaks (try/catch to avoid crash on edge cases)
try
    if dist > 0
        [pks, locs] = findpeaks(zDet, t, ...
            'MinPeakHeight', upperBound, ...
            'MinPeakDistance', dist);
    else
        [pks, locs] = findpeaks(zDet, t, ...
            'MinPeakHeight', upperBound);
    end
catch
    pks = [];
    locs = [];
end
end

function [t, labels] = localLoadUSVCalls(usvMat)
% Load DeepSqueak Calls and extract:
%   t      : call start time in seconds
%   labels : call labels (cell array of strings)

S = load(usvMat);

% Try to locate Calls variable first
Calls = [];
fn = fieldnames(S);

for i = 1:numel(fn)
    if strcmpi(fn{i}, 'Calls')
        Calls = S.(fn{i});
        break;
    end
end

% If no "Calls", fall back to first table/struct-like variable
if isempty(Calls)
    for i = 1:numel(fn)
        v = S.(fn{i});
        if istable(v) || isstruct(v)
            Calls = v;
            break;
        end
    end
end

if isempty(Calls)
    error('Could not find Calls in USV MAT.');
end

% Extract time and label from Calls
[t, labels] = localExtractTimeAndLabel(Calls);
end

function [t, labels] = localExtractTimeAndLabel(Calls)
% Handles Calls as table or struct.
% We try multiple common field/column names, but keep it beginner-readable.

labels = {};

if istable(Calls)

    vars = Calls.Properties.VariableNames;

    % --- TIME ---
    t = [];
    if any(strcmpi(vars, 'Box'))
        box = Calls.(vars{strcmpi(vars, 'Box')});
        t = localBoxToTime(box);
    else
        timeCandidates = vars(contains(lower(string(vars)), 'time'));
        if ~isempty(timeCandidates)
            t = double(Calls.(timeCandidates{1}));
            t = t(:);
        end
    end

    if isempty(t)
        t = zeros(0, 1);
    end

    % --- LABEL ---
    labelCandidates = {'Type','Label','Category','Class','CallType','callType'};
    lab = [];

    for i = 1:numel(labelCandidates)
        idx = find(strcmpi(vars, labelCandidates{i}), 1);
        if ~isempty(idx)
            lab = Calls.(vars{idx});
            break;
        end
    end

    if isempty(lab)
        % fallback: first categorical/string/cellstr column
        for i = 1:numel(vars)
            v = Calls.(vars{i});
            if iscategorical(v) || isstring(v) || iscellstr(v)
                lab = v;
                break;
            end
        end
    end

    if isempty(lab)
        labels = repmat({'USV'}, numel(t), 1);
    else
        labels = cellstr(string(lab));
        labels = labels(:);
    end

elseif isstruct(Calls)

    % --- TIME ---
    if isfield(Calls, 'Box')
        t = localBoxToTime(Calls.Box);
    elseif isfield(Calls, 'StartTime')
        t = double([Calls.StartTime]');
    elseif isfield(Calls, 'StartTime_s')
        t = double([Calls.StartTime_s]');
    else
        % fallback: any numeric field containing 'time'
        fns = fieldnames(Calls);
        t = [];

        for i = 1:numel(fns)
            if contains(lower(fns{i}), 'time')
                v = Calls.(fns{i});
                if isnumeric(v)
                    t = double(v(:));
                    break;
                end
            end
        end

        if isempty(t)
            error('Could not find time in Calls struct.');
        end
    end

    % --- LABEL ---
    labelFields = {'Type','Label','Category','Class','callType'};
    lab = [];

    for i = 1:numel(labelFields)
        if isfield(Calls, labelFields{i})
            lab = {Calls.(labelFields{i})}';
            break;
        end
    end

    if isempty(lab)
        labels = repmat({'USV'}, numel(t), 1);
    else
        labels = cellstr(string(lab));
        labels = labels(:);
    end

else
    error('Calls has unsupported type.');
end

% Ensure size match (pad/truncate if needed)
t = t(:);

if numel(labels) ~= numel(t)
    n = min(numel(labels), numel(t));
    t = t(1:n);
    labels = labels(1:n);
end
end

function t = localBoxToTime(box)
% Convert Calls.Box to start-time vector.
% Supports:
%   - numeric matrix (NxM)
%   - cell array where each cell holds a numeric vector
%   - unknown types (best-effort fallback)

if isempty(box)
    t = zeros(0, 1);
    return;
end

if isnumeric(box)
    if size(box, 2) >= 1
        t = double(box(:, 1));
    else
        t = double(box(:));
    end
    return;
end

if iscell(box)
    n = numel(box);
    t = zeros(n, 1);

    for i = 1:n
        bi = box{i};
        if isnumeric(bi) && ~isempty(bi)
            t(i) = double(bi(1));
        else
            t(i) = NaN;
        end
    end
    return;
end

% Fallback try
try
    t = double(box(:, 1));
catch
    t = zeros(0, 1);
end
end

function s = localNormLabel(sIn)
% Normalize labels so we can match them reliably:
%   - lower-case
%   - remove spaces/dashes/punctuation
%   - map common variants to the template spelling

s = lower(string(sIn));
s = strtrim(s);

% Remove all non-alphanumeric characters
s = regexprep(s, '[^a-z0-9]', '');

% Map common variants
switch char(s)
    case {'miscellaneous','misc','miscallaneous','miscellaneuous'}
        s = "miscellaneuous";
    case {'22khz','22kh','22k','22kilo','22kilohz'}
        s = "22khz";
    case {'flattrill'}
        s = "flattrill";
    case {'multistep'}
        s = "multistep";
    case {'trillwithjumps','trilljumps'}
        s = "trillwithjumps";
    case {'invertedu'}
        s = "invertedu";
    otherwise
        % keep as-is
end

% Return char (many parts of this script store keys as char)
s = char(s);
end

function [a, b] = localReadSyncMapping(syncXlsx)
% Read mapping parameters a,b from the 'sync_mapping' sheet.
% Expected rows contain:
%   "a (drift)" | <value>
%   "b (s)"     | <value>

T = readcell(syncXlsx, 'Sheet', 'sync_mapping');

a = [];
b = [];

for i = 1:size(T, 1)

    % Need at least 2 columns
    if size(T, 2) < 2
        continue;
    end

    key = string(T{i, 1});
    val = T{i, 2};

    keyL = lower(key);

    if contains(keyL, 'a') && contains(keyL, 'drift')
        a = str2double(string(val));
    elseif contains(keyL, 'b') && contains(keyL, '(s)')
        b = str2double(string(val));
    end
end

if isempty(a) || isnan(a)
    error('Could not read a (drift) from sync_mapping.');
end

if isempty(b) || isnan(b)
    error('Could not read b (s) from sync_mapping.');
end
end

function [a, b] = localSegmentBounds(k, edges)
% Segment bounds helper.
% k = 1 Full, k = 2 Seg1, k = 3 Seg2, k = 4 Seg3

switch k
    case 1
        a = edges(1);
        b = edges(4) + eps;  % include end
    case 2
        a = edges(1);
        b = edges(2);
    case 3
        a = edges(2);
        b = edges(3);
    case 4
        a = edges(3);
        b = edges(4) + eps;  % include end
    otherwise
        a = edges(1);
        b = edges(4) + eps;
end
end
