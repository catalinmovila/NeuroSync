function outXlsx = FP_TTL_USV_EventLocked_overview(varargin)
% FP_TTL_USV_EventLocked_overview
% -------------------------------------------------------------------------
% GOAL
%   Create a per-second Excel timeline for one experiment.
%
%   Each row represents ONE second bin:
%       row "0"   -> [0,1) seconds
%       row "1"   -> [1,2) seconds
%       row "2"   -> [2,3) seconds
%       ...
%
%   The columns report how many events happened inside that second:
%       - TTL events (20 / 40 / 60 / 80 ms)
%       - Peaks (from corrected FP MAT)
%       - USV subtypes (shifted preferred)
%
% MISSING-DATA RULE
%   - Missing modality columns are filled with "X".
%   - Available modality columns contain numeric counts.
%
% INPUTS (Name/Value)
%   'FPmat'            : corrected FP MAT (optional)
%   'TTLcsv'           : TTLBox CSV (optional)
%   'USVmat'           : DeepSqueak MAT (optional)
%   'OutXlsx'          : output Excel path (required)
%   'SyncMappingXlsx'  : optional mapping t_TTLBox = a*t_audio + b
%
% IMPORTANT RULES
%   - Shifted USV MAT is preferred before calling this function.
%   - If a raw USV MAT is used and SyncMappingXlsx is available,
%     the mapping is applied once here.
%   - Time axis length is based on the latest available timestamp across
%     TTL / Peaks / USV / FP duration.
%   - A blank row is added after the second-by-second timeline, followed by
%     a TOTAL row that sums every available numeric column.
% -------------------------------------------------------------------------

%% 1) Defaults
fpMat    = "";
ttlCsv   = "";
usvMat   = "";
outXlsx  = "";
syncXlsx = "";

%% 2) Parse name/value pairs
if ~isempty(varargin)
    if mod(numel(varargin), 2) ~= 0
        error('Inputs must be name/value pairs.');
    end

    for i = 1:2:numel(varargin)
        nameIn = lower(string(varargin{i}));
        valIn  = varargin{i+1};

        if nameIn == "fpmat"
            fpMat = string(valIn);
        elseif nameIn == "ttlcsv"
            ttlCsv = string(valIn);
        elseif nameIn == "usvmat"
            usvMat = string(valIn);
        elseif nameIn == "outxlsx"
            outXlsx = string(valIn);
        elseif nameIn == "syncmappingxlsx"
            syncXlsx = string(valIn);
        else
            error('Unknown parameter name: %s', nameIn);
        end
    end
end

%% 3) Output path
if strlength(outXlsx) == 0
    [f, p] = uiputfile({'*.xlsx','Excel (*.xlsx)'}, 'Save event-locked Excel as');
    if isequal(f, 0)
        error('No output Excel selected.');
    end
    outXlsx = string(fullfile(p, f));
end

%% 4) Availability flags
hasFP   = (strlength(fpMat) > 0)   && isfile(fpMat);
hasTTL  = (strlength(ttlCsv) > 0)  && isfile(ttlCsv);
hasUSV  = (strlength(usvMat) > 0)  && isfile(usvMat);
hasSync = (strlength(syncXlsx) > 0) && isfile(syncXlsx);

if ~hasFP && ~hasTTL && ~hasUSV
    error('Need at least one valid input among FP MAT / TTL CSV / USV MAT.');
end

%% 5) Fixed column labels
ttlHeaders = { ...
    'Left lever press (20 ms)', ...
    'Right lever press (40 ms)', ...
    'Drug reward (60 ms)', ...
    'Food reward (80 ms)'};

usvHeaders = { ...
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
    'Miscellaneuous'};

%% 6) Load TTL events
ttl = struct();
ttl.times_s = zeros(0,1);
ttl.code_ms = zeros(0,1);

if hasTTL
    ttl = localParseTTLBoxRaw(ttlCsv);
end

%% 7) Load FP peaks
fpTime_s  = zeros(0,1);
peakTimes = zeros(0,1);

if hasFP
    [fpTime_s, fpSignal] = localLoadCorrectedFP(fpMat);

    % Force FP to start at 0 seconds.
    if ~isempty(fpTime_s)
        fpTime_s = fpTime_s - fpTime_s(1);
    end

    [~, peakTimes] = localFindPeaks(fpTime_s, fpSignal);
    peakTimes = peakTimes(:);
end

%% 8) Load USV events
usvTimes_s = zeros(0,1);
usvNorm    = cell(0,1);

if hasUSV
    [usvTimes_s, callLabels] = localLoadUSVCalls(usvMat);
    usvTimes_s = usvTimes_s(:);

    % Apply mapping only if the selected file is NOT already shifted.
    if ~contains(lower(string(usvMat)), "_shifted") && hasSync
        [mapA, mapB] = localReadSyncMapping(syncXlsx);
        usvTimes_s = mapA .* usvTimes_s + mapB;
    end

    % Normalize labels
    usvNorm = cell(numel(callLabels), 1);
    for i = 1:numel(callLabels)
        key = localNormLabel(callLabels{i});
        if isempty(key)
            key = 'unclear';
        end
        usvNorm{i} = key;
    end
end

%% 9) Determine last second of the timeline
maxVals = 0;

if ~isempty(ttl.times_s)
    maxVals(end+1,1) = max(ttl.times_s); %#ok<AGROW>
end

if ~isempty(peakTimes)
    maxVals(end+1,1) = max(peakTimes); %#ok<AGROW>
end

if ~isempty(usvTimes_s)
    maxVals(end+1,1) = max(usvTimes_s); %#ok<AGROW>
end

if ~isempty(fpTime_s)
    maxVals(end+1,1) = max(fpTime_s); %#ok<AGROW>
end

maxVals = maxVals(isfinite(maxVals));
if isempty(maxVals)
    lastSec = 0;
else
    lastSec = floor(max(maxVals));
    if lastSec < 0
        lastSec = 0;
    end
end

nRows = lastSec + 1;
timeVec = (0:lastSec)';

%% 10) Precompute available modality counts
% TTL
ttl20 = zeros(nRows, 1);
ttl40 = zeros(nRows, 1);
ttl60 = zeros(nRows, 1);
ttl80 = zeros(nRows, 1);

if hasTTL
    ttl20 = localBinCounts(ttl.times_s(ttl.code_ms == 20), lastSec);
    ttl40 = localBinCounts(ttl.times_s(ttl.code_ms == 40), lastSec);
    ttl60 = localBinCounts(ttl.times_s(ttl.code_ms == 60), lastSec);
    ttl80 = localBinCounts(ttl.times_s(ttl.code_ms == 80), lastSec);
end

% Peaks
peakCounts = zeros(nRows, 1);
if hasFP
    peakCounts = localBinCounts(peakTimes, lastSec);
end

% USV templates
nUSVcols = numel(usvHeaders);
tmplNorm = cell(nUSVcols, 1);
for r = 1:nUSVcols
    tmplNorm{r} = localNormLabel(usvHeaders{r});
end

fallbackUSVidx = find(strcmp(tmplNorm, 'unclear'), 1);
if isempty(fallbackUSVidx)
    fallbackUSVidx = 1;
end

usvCounts = zeros(nRows, nUSVcols);

if hasUSV
    for i = 1:numel(usvTimes_s)
        t = usvTimes_s(i);

        if ~isfinite(t)
            continue;
        end

        if t < 0
            continue;
        end

        idxRow = floor(t) + 1;
        if idxRow < 1 || idxRow > nRows
            continue;
        end

        key = usvNorm{i};
        idxLabel = localFindTemplateIndex(key, tmplNorm, fallbackUSVidx);

        usvCounts(idxRow, idxLabel) = usvCounts(idxRow, idxLabel) + 1;
    end
end

%% 11) Build Excel cell matrix
headers = [{'Time_s'}, ttlHeaders, {'Peaks'}, usvHeaders'];
nCols = numel(headers);

% +1 header, +nRows data, +1 blank row, +1 total row
C = cell(nRows + 3, nCols);

% Header row
for c = 1:nCols
    C{1, c} = headers{c};
end

% Time column
for r = 1:nRows
    C{r+1, 1} = timeVec(r);
end

% TTL columns
ttlData = {ttl20, ttl40, ttl60, ttl80};
for c = 1:4
    if hasTTL
        for r = 1:nRows
            C{r+1, 1+c} = ttlData{c}(r);
        end
    else
        for r = 1:nRows
            C{r+1, 1+c} = 'X';
        end
    end
end

% Peaks column
peakCol = 1 + 4 + 1;
if hasFP
    for r = 1:nRows
        C{r+1, peakCol} = peakCounts(r);
    end
else
    for r = 1:nRows
        C{r+1, peakCol} = 'X';
    end
end

% USV columns
firstUSVcol = peakCol + 1;

if hasUSV
    for u = 1:nUSVcols
        for r = 1:nRows
            C{r+1, firstUSVcol + (u-1)} = usvCounts(r, u);
        end
    end
else
    for u = 1:nUSVcols
        for r = 1:nRows
            C{r+1, firstUSVcol + (u-1)} = 'X';
        end
    end
end

% Blank spacer row
blankRow = nRows + 2;
for c = 1:nCols
    C{blankRow, c} = '';
end

% TOTAL row
totalRow = nRows + 3;
C{totalRow, 1} = 'TOTAL';

for c = 2:nCols
    colData = C(2:(nRows+1), c);
    sumVal = 0;
    hasNumeric = false;

    for r = 1:numel(colData)
        v = colData{r};
        if isnumeric(v) && isfinite(v)
            sumVal = sumVal + double(v);
            hasNumeric = true;
        end
    end

    if hasNumeric
        C{totalRow, c} = sumVal;
    else
        C{totalRow, c} = 'X';
    end
end

%% 12) Write main sheet
writecell(C, outXlsx, 'Sheet', 'EventLocked', 'Range', 'A1');

%% 13) Write small info sheet
info = {
    'Rule', 'Value'
    'Time bin', '[t, t+1) seconds; row label is the start second'
    'TTL source', localPrettyMissing(hasTTL, ttlCsv)
    'FP Peaks source', localPrettyMissing(hasFP, fpMat)
    'USV source', localPrettyMissing(hasUSV, usvMat)
    'Sync mapping used', localYesNo(~contains(lower(string(usvMat)), "_shifted") && hasUSV && hasSync)
    'Missing modality marker', 'X'
    'Unknown USV subtype handling', 'Counted under Unclear'
    'Final rows', 'One blank row + one TOTAL row'
    };

writecell(info, outXlsx, 'Sheet', 'Info', 'Range', 'A1');

fprintf('Saved event-locked Excel to: %s\n', outXlsx);

end

%% ============================== helpers ==============================

function txt = localPrettyMissing(tf, p)
if tf
    txt = char(string(p));
else
    txt = 'Missing';
end
end

function txt = localYesNo(tf)
if tf
    txt = 'Yes';
else
    txt = 'No';
end
end

function counts = localBinCounts(times_s, lastSec)
nRows = lastSec + 1;
counts = zeros(nRows, 1);

if isempty(times_s)
    return;
end

times_s = double(times_s(:));

for i = 1:numel(times_s)
    t = times_s(i);

    if ~isfinite(t)
        continue;
    end

    if t < 0
        continue;
    end

    idx = floor(t) + 1;

    if idx >= 1 && idx <= nRows
        counts(idx) = counts(idx) + 1;
    end
end
end

function ttl = localParseTTLBoxRaw(ttlCsv)
% Read TTLBox CSV robustly and keep RAW event times from the file.
% Unlike the overview exporter, this function does NOT subtract the first
% pulse time, because the user wants the full second-by-second timeline.

ttl = struct();
ttl.times_s = zeros(0,1);
ttl.code_ms = zeros(0,1);

T = readtable(ttlCsv, 'Delimiter', ',', 'ReadVariableNames', false);

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

for i = 1:(N-1)
    if isFalse(i) && isTrue(i+1)
        w = (time_s(i+1) - time_s(i)) * 1000;
        if isfinite(w) && w > 0
            starts(end+1, 1)    = time_s(i); %#ok<AGROW>
            widths_ms(end+1, 1) = w;         %#ok<AGROW>
        end
    end
end

if isempty(starts)
    return;
end

targets = [20 40 60 80];
codes   = zeros(size(widths_ms));
valid   = false(size(widths_ms));

for k = 1:numel(widths_ms)
    [d, idx] = min(abs(widths_ms(k) - targets));
    tgt = targets(idx);

    % Slightly more permissive tolerance for real TTL logs.
    if d <= 0.10 * tgt
        codes(k) = tgt;
        valid(k) = true;
    end
end

ttl.times_s = starts(valid);
ttl.code_ms = codes(valid);
end

function [t, z] = localLoadCorrectedFP(fpMat)
S = load(fpMat);

if isfield(S, 'correctedSignalTable')
    T = S.correctedSignalTable;

    if istable(T)
        if any(strcmp(T.Properties.VariableNames, 'Time_s'))
            t = T.Time_s;
        else
            t = T{:, 1};
        end

        if any(strcmp(T.Properties.VariableNames, 'CorrectedSignal'))
            z = T.CorrectedSignal;
        else
            z = T{:, 2};
        end
    else
        fn = fieldnames(T);

        if any(strcmp(fn, 'Time_s'))
            t = T.Time_s;
        else
            t = T.(fn{1});
        end

        if any(strcmp(fn, 'CorrectedSignal'))
            z = T.CorrectedSignal;
        else
            if numel(fn) < 2
                error('correctedSignalTable struct has too few fields.');
            end
            z = T.(fn{2});
        end
    end

elseif isfield(S, 'tablediffRelative')
    T = S.tablediffRelative;

    if istable(T)
        if any(strcmp(T.Properties.VariableNames, 'Var1'))
            t = T.Var1;
            z = T.Var2;
        else
            t = T{:, 1};
            z = T{:, 2};
        end
    else
        t = T(:, 1);
        z = T(:, 2);
    end

else
    error('FP MAT does not contain correctedSignalTable or tablediffRelative.');
end

if isrow(t), t = t'; end
if isrow(z), z = z'; end

t = double(t);
z = double(z);
end

function [pks, locs] = localFindPeaks(t, z)
if numel(t) < 5
    pks = [];
    locs = [];
    return;
end

upperBoundController = 1.0;
distanceBetweenPeaksController = 0.0075;

t = t(:);
zRaw = z(:);

zmean = mean(zRaw, 'omitnan');
zstd  = std(zRaw, 'omitnan');

upperBound = zmean + (upperBoundController * zstd);
zDet = zRaw - zmean;

dist = distanceBetweenPeaksController * (t(end) - t(1));
if ~isfinite(dist) || dist <= 0
    dist = 0;
end

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
S = load(usvMat);

Calls = [];
fn = fieldnames(S);

for i = 1:numel(fn)
    if strcmpi(fn{i}, 'Calls')
        Calls = S.(fn{i});
        break;
    end
end

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

[t, labels] = localExtractTimeAndLabel(Calls);
end

function [t, labels] = localExtractTimeAndLabel(Calls)
labels = {};

if istable(Calls)
    vars = Calls.Properties.VariableNames;

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
        for i = 1:numel(vars)
            v = Calls.(vars{i});
            if iscategorical(v) || isstring(v) || iscellstr(v)
                lab = v;
                break;
            end
        end
    end

    if isempty(lab)
        labels = repmat({'Unclear'}, numel(t), 1);
    else
        labels = cellstr(string(lab));
        labels = labels(:);
    end

elseif isstruct(Calls)
    if isfield(Calls, 'Box')
        t = localBoxToTime(Calls.Box);
    elseif isfield(Calls, 'StartTime')
        t = double([Calls.StartTime]');
    elseif isfield(Calls, 'StartTime_s')
        t = double([Calls.StartTime_s]');
    else
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

    labelFields = {'Type','Label','Category','Class','callType'};
    lab = [];

    for i = 1:numel(labelFields)
        if isfield(Calls, labelFields{i})
            lab = {Calls.(labelFields{i})}';
            break;
        end
    end

    if isempty(lab)
        labels = repmat({'Unclear'}, numel(t), 1);
    else
        labels = cellstr(string(lab));
        labels = labels(:);
    end

else
    error('Calls has unsupported type.');
end

t = t(:);

if numel(labels) ~= numel(t)
    n = min(numel(labels), numel(t));
    t = t(1:n);
    labels = labels(1:n);
end
end

function t = localBoxToTime(box)
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

try
    t = double(box(:, 1));
catch
    t = zeros(0, 1);
end
end

function s = localNormLabel(sIn)
s = lower(string(sIn));
s = strtrim(s);
s = regexprep(s, '[^a-z0-9]', '');

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
    case {'usv','unknown','other','otherusv','noise'}
        s = "unclear";
    otherwise
        % keep as-is
end

s = char(s);
end

function idx = localFindTemplateIndex(key, tmplNorm, fallbackIdx)
idx = fallbackIdx;

for r = 1:numel(tmplNorm)
    if strcmp(key, tmplNorm{r})
        idx = r;
        return;
    end
end
end

function [a, b] = localReadSyncMapping(syncXlsx)
T = readcell(syncXlsx, 'Sheet', 'sync_mapping');

a = [];
b = [];

for i = 1:size(T, 1)
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
