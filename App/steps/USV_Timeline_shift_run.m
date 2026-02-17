function [outUsvMat, a, b] = USV_Timeline_shift_run(mapFile, usvMat, varargin)
% USV_Timeline_shift_run  (PASS 2: extra-declustered + heavy comments)
% -------------------------------------------------------------------------
% PURPOSE
%   Apply a time-base mapping to a DeepSqueak detection .mat file so that
%   call times (USVs) are expressed in the TTLBox / photometry time base.
%
% MAPPING CONVENTION USED IN THIS PROJECT
%   We always store mapping as:
%       t_TTLBox = a * t_audio + b
%
%   Where:
%       t_audio  = time base inside the WAV/DeepSqueak detection (seconds)
%       t_TTLBox = time base inside TTLBox / photometry (seconds)
%       a        = drift (usually ~1, handles clock drift)
%       b        = offset in seconds
%
% INPUTS
%   mapFile : *_SYNC_MAPPING.xlsx created by TTL_WAV_vs_TTLBox_run.m
%             Must contain a 2-column table with headers: Field | Value
%             and rows for: "a (drift)" and "b (s)"
%
%   usvMat  : DeepSqueak detection MAT file. Must contain a variable holding
%             call detections, usually named "Calls".
%
% OPTIONAL NAME/VALUE PAIRS
%   'OutMat'    : output file path. Default: <usvMat> with "_SHIFTED.mat"
%   'Overwrite' : true/false. If true, overwrites the input MAT (not recommended).
%
% OUTPUTS
%   outUsvMat : path to the shifted MAT that was saved
%   a, b      : mapping parameters read from mapFile
%
% -------------------------------------------------------------------------
% IMPORTANT NOTES
%   - This function does NOT change call labels, scores, etc.
%   - It only changes call timing fields (start/end or Box column).
%   - If Calls.Box exists, we modify:
%         Box(:,1) start time  -> a*t + b
%         Box(:,3) duration    -> a*dur
%     Duration is scaled by 'a' because drift changes elapsed time.
% -------------------------------------------------------------------------


%% =====================================================================
% 1) DEFAULTS (explicit)
% =====================================================================
outUsvMat = "";      % output path (empty until we decide it)
overwrite = false;   % default: do not overwrite input file


%% =====================================================================
% 2) INPUT CLEANUP
% =====================================================================
% Allow missing inputs (so errors are clear)
if nargin < 1
    mapFile = "";
end
if nargin < 2
    usvMat = "";
end

% Convert to string for easier checks
mapFile = string(mapFile);
usvMat  = string(usvMat);


%% =====================================================================
% 3) PARSE NAME/VALUE OPTIONS (manual, student-style)
% =====================================================================
% Expected: 'OutMat', <path>, 'Overwrite', true/false
if ~isempty(varargin)

    % Must come in pairs
    if mod(numel(varargin), 2) ~= 0
        error('USV_Timeline_shift_run:BadArgs', ...
            'Options must be name/value pairs, e.g. ''OutMat'',''file.mat''.');
    end

    % Walk through pairs
    for k = 1:2:numel(varargin)

        optName = string(varargin{k});
        optVal  = varargin{k+1};

        % Normalize the option name
        optKey = lower(strtrim(optName));

        if optKey == "outmat"
            outUsvMat = string(optVal);

        elseif optKey == "overwrite"
            overwrite = logical(optVal);

            % Enforce scalar true/false
            if ~isscalar(overwrite)
                error('USV_Timeline_shift_run:BadOverwrite', ...
                    'Overwrite must be a scalar true/false.');
            end

        else
            error('USV_Timeline_shift_run:BadArgs', ...
                'Unknown option: %s', optName);
        end
    end
end


%% =====================================================================
% 4) VALIDATE INPUT FILES
% =====================================================================
if strlength(mapFile) == 0 || ~isfile(mapFile)
    error('USV_Timeline_shift_run:MissingMap', ...
        'SYNC mapping XLSX not found: %s', mapFile);
end

if strlength(usvMat) == 0 || ~isfile(usvMat)
    error('USV_Timeline_shift_run:MissingUSV', ...
        'USV detection MAT not found: %s', usvMat);
end


%% =====================================================================
% 5) READ MAPPING PARAMETERS a,b FROM EXCEL
% =====================================================================
[a, b] = readSyncMappingAB_simple(mapFile);


%% =====================================================================
% 6) DECIDE OUTPUT PATH
% =====================================================================
% Rule:
%   - If overwrite is true => save back into the same file
%   - Else if OutMat provided => use it
%   - Else default => <same folder>/<name>_SHIFTED.mat
if overwrite

    % Overwrite the input file
    outUsvMat = usvMat;

else
    % If user did not provide OutMat, build a default name
    if strlength(outUsvMat) == 0
        [p0, n0, ~] = fileparts(usvMat);
        outUsvMat = fullfile(p0, n0 + "_SHIFTED.mat");
    end
end


%% =====================================================================
% 7) LOAD MAT AND LOCATE THE CALLS VARIABLE
% =====================================================================
S = load(usvMat);

% DeepSqueak usually stores calls in S.Calls
% But we also support other variable names that contain "call"
callsVar = findCallsVar_simple(S);

% Extract Calls (could be table or struct)
Calls = S.(callsVar);


%% =====================================================================
% 8) APPLY MAPPING TO Calls
% =====================================================================
% This function supports:
%   - Calls as a table (most common)
%   - Calls as a struct array (some export formats)
Calls = applyMappingToCalls_simple(Calls, a, b);


%% =====================================================================
% 9) SAVE UPDATED MAT (keep ALL original variables)
% =====================================================================
% Put updated Calls back into the loaded struct
S.(callsVar) = Calls;

% Save as a "struct MAT" so all variables are preserved
try
    save(outUsvMat, '-struct', 'S');
catch ME
    % If file is too big, MATLAB requires -v7.3
    warning('Default save failed (%s). Retrying with -v7.3...', ME.message);
    save(outUsvMat, '-struct', 'S', '-v7.3');
end

% Console print (helpful when running in command window)
fprintf('[USV_Timeline_shift_run] a=%.12g, b=%.12g s | %s -> %s\n', ...
    a, b, usvMat, outUsvMat);

end


%% =====================================================================
% LOCAL HELPER FUNCTIONS (kept small, explicit, beginner-readable)
% =====================================================================

function [a, b] = readSyncMappingAB_simple(mapFile)
% Read mapping parameters a,b from a 2-column Excel sheet:
%   Field | Value
%
% Expected Field strings:
%   "a (drift)"
%   "b (s)"

T = readtable(mapFile, 'FileType', 'spreadsheet', 'ReadVariableNames', true);

% Check expected headers exist
if ~all(ismember({'Field','Value'}, T.Properties.VariableNames))
    error('USV_Timeline_shift_run:BadMap', ...
        'SYNC_MAPPING.xlsx must contain columns named Field and Value.');
end

% Read a and b using explicit helper
a = readFieldNumeric_simple(T, "a (drift)");
b = readFieldNumeric_simple(T, "b (s)");

% Validate numeric
if isnan(a) || isnan(b)
    error('USV_Timeline_shift_run:BadMap', ...
        'Could not read a/b. Expected Field rows: "a (drift)" and "b (s)".');
end
end

function x = readFieldNumeric_simple(T, fieldName)
% Find a matching Field row and parse its Value as a number.
% Returns NaN if field does not exist or parsing fails.

x = NaN;

% Find first match (case-insensitive)
idx = find(strcmpi(string(T.Field), string(fieldName)), 1, 'first');
if isempty(idx)
    return;
end

v = T.Value(idx);

% Value might be numeric or text
if isnumeric(v)
    x = double(v);
else
    x = str2double(string(v));
end
end

function callsVar = findCallsVar_simple(S)
% Find which variable inside MAT contains calls.
% Preferred: "Calls"
% Fallback: first variable name that contains "call" (case-insensitive).

callsVar = "";

% Best case: Calls exists
if isfield(S, 'Calls')
    callsVar = "Calls";
    return;
end

% Otherwise scan fields
fn = fieldnames(S);
if isempty(fn)
    error('USV_Timeline_shift_run:NoCalls', 'MAT file is empty.');
end

for i = 1:numel(fn)
    nameLower = lower(string(fn{i}));
    if contains(nameLower, "call")
        callsVar = string(fn{i});
        break;
    end
end

if strlength(callsVar) == 0
    error('USV_Timeline_shift_run:NoCalls', ...
        'Could not find a Calls variable in MAT file.');
end
end

function CallsOut = applyMappingToCalls_simple(CallsIn, a, b)
% Dispatch based on the Calls data type.

CallsOut = CallsIn;

if istable(CallsIn)
    CallsOut = applyMappingToCallsTable_simple(CallsIn, a, b);
    return;
end

if isstruct(CallsIn)
    CallsOut = applyMappingToCallsStruct_simple(CallsIn, a, b);
    return;
end

error('USV_Timeline_shift_run:Unsupported', ...
    'Calls is neither a table nor a struct array.');
end

function CallsT = applyMappingToCallsTable_simple(CallsT, a, b)
% Apply mapping when Calls is a table.

varNames = CallsT.Properties.VariableNames;

% Case A: DeepSqueak typical format has Calls.Box
if any(strcmpi(varNames, 'Box'))

    % Calls.Box can be numeric matrix (N x 4) OR cell array (Nx1) of 1x4 vectors.
    Box = CallsT.Box;

    % Extract start times and durations (in audio time base)
    [tStart, tDur, isCellBox] = extractStartDurFromBox_simple(Box);

    % Apply mapping
    tStartNew = a .* tStart + b;
    tDurNew   = a .* tDur;

    % Write back into Box
    CallsT.Box = writeStartDurToBox_simple(Box, tStartNew, tDurNew, isCellBox);
    return;
end

% Case B: No Box column, try to find Start/End columns
[startVar, endVar] = guessStartEndVarsFromTable_simple(CallsT);

startAudio = ensureNumeric_simple(CallsT.(startVar));
endAudio   = ensureNumeric_simple(CallsT.(endVar));

CallsT.(startVar) = a .* startAudio + b;
CallsT.(endVar)   = a .* endAudio   + b;
end

function CallsS = applyMappingToCallsStruct_simple(CallsS, a, b)
% Apply mapping when Calls is a struct array.

if isempty(CallsS)
    return;
end

% Case A: struct has Box field
if isfield(CallsS, 'Box')

    for i = 1:numel(CallsS)

        Box = CallsS(i).Box;

        [tStart, tDur, isCellBox] = extractStartDurFromBox_simple(Box);

        tStartNew = a .* tStart + b;
        tDurNew   = a .* tDur;

        CallsS(i).Box = writeStartDurToBox_simple(Box, tStartNew, tDurNew, isCellBox);
    end
    return;
end

% Case B: struct has Start/End fields instead
[startField, endField] = guessStartEndFieldsFromStruct_simple(CallsS);

for i = 1:numel(CallsS)
    CallsS(i).(startField) = a .* ensureNumeric_simple(CallsS(i).(startField)) + b;
    CallsS(i).(endField)   = a .* ensureNumeric_simple(CallsS(i).(endField))   + b;
end
end

function y = ensureNumeric_simple(y)
% Convert to numeric column vector.
% Supports numeric, string/char, and cell containing text/numbers.

if isnumeric(y)
    y = double(y(:));
    return;
end

y = str2double(string(y));
y = double(y(:));
end

function [tStart, tDur, isCellBox] = extractStartDurFromBox_simple(Box)
% Extract start time and duration from Calls.Box
% DeepSqueak convention (most common):
%   Box = [tStart, fLow, dur, bw]  (dur in seconds)

isCellBox = false;

% Case 1: numeric matrix (N x >=3)
if isnumeric(Box)
    if size(Box, 2) < 3
        error('USV_Timeline_shift_run:BadBox', ...
            'Calls.Box numeric but has <3 columns.');
    end
    tStart = double(Box(:,1));
    tDur   = double(Box(:,3));
    return;
end

% Case 2: cell array where each row holds a numeric vector
if iscell(Box)
    isCellBox = true;

    n = size(Box,1);
    tStart = nan(n,1);
    tDur   = nan(n,1);

    for i = 1:n
        row = Box{i};

        % Unwrap nested single-cell layers (some MAT files store Box this way)
        while iscell(row) && numel(row) == 1
            row = row{1};
        end

        if ~isnumeric(row) || isempty(row) || numel(row) < 3
            error('USV_Timeline_shift_run:BadBox', ...
                'Calls.Box row %d is not numeric with >=3 elements.', i);
        end

        row = double(row(:)');

        tStart(i) = row(1);
        tDur(i)   = row(3);
    end

    return;
end

error('USV_Timeline_shift_run:BadBox', 'Calls.Box is neither numeric nor cell.');
end

function BoxOut = writeStartDurToBox_simple(BoxIn, tStartNew, tDurNew, isCellBox)
% Write updated start/duration back into Calls.Box (numeric or cell).

if ~isCellBox
    BoxOut = BoxIn;
    BoxOut(:,1) = tStartNew;
    BoxOut(:,3) = tDurNew;
    return;
end

n = size(BoxIn,1);
BoxOut = BoxIn;

for i = 1:n
    row = BoxIn{i};

    while iscell(row) && numel(row) == 1
        row = row{1};
    end

    row = double(row(:)');

    % Update start time + duration
    row(1) = tStartNew(i);

    if numel(row) >= 3
        row(3) = tDurNew(i);
    end

    BoxOut{i} = row;
end
end

function [startVar, endVar] = guessStartEndVarsFromTable_simple(CallsT)
% If Calls.Box does not exist, try to guess Start/End columns.
% We search the variable names for "start", "end", "stop", etc.

v = lower(string(CallsT.Properties.VariableNames));

% --- Start ---
startIdx = find(contains(v, "start") & contains(v, "time"), 1, 'first');
if isempty(startIdx)
    startIdx = find(contains(v, "tstart"), 1, 'first');
end
if isempty(startIdx)
    startIdx = find(contains(v, "start"), 1, 'first');
end

% --- End ---
endIdx = find((contains(v, "end") | contains(v, "stop")) & contains(v, "time"), 1, 'first');
if isempty(endIdx)
    endIdx = find(contains(v, "tend") | contains(v, "tstop"), 1, 'first');
end
if isempty(endIdx)
    endIdx = find(contains(v, "end") | contains(v, "stop"), 1, 'first');
end

if isempty(startIdx) || isempty(endIdx)
    error('USV_Timeline_shift_run:NoStartEnd', ...
        'Could not find Start/End time columns in Calls table.');
end

startVar = CallsT.Properties.VariableNames{startIdx};
endVar   = CallsT.Properties.VariableNames{endIdx};
end

function [startField, endField] = guessStartEndFieldsFromStruct_simple(CallsS)
% Same as table version, but for struct field names.

fn = fieldnames(CallsS);
f  = lower(string(fn));

% --- Start ---
startIdx = find(contains(f, "start") & contains(f, "time"), 1, 'first');
if isempty(startIdx)
    startIdx = find(contains(f, "tstart"), 1, 'first');
end
if isempty(startIdx)
    startIdx = find(contains(f, "start"), 1, 'first');
end

% --- End ---
endIdx = find((contains(f, "end") | contains(f, "stop")) & contains(f, "time"), 1, 'first');
if isempty(endIdx)
    endIdx = find(contains(f, "tend") | contains(f, "tstop"), 1, 'first');
end
if isempty(endIdx)
    endIdx = find(contains(f, "end") | contains(f, "stop"), 1, 'first');
end

if isempty(startIdx) || isempty(endIdx)
    error('USV_Timeline_shift_run:NoStartEnd', ...
        'Could not find Start/End time fields in Calls struct.');
end

startField = fn{startIdx};
endField   = fn{endIdx};
end
