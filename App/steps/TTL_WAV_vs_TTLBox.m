function out = TTL_WAV_vs_TTLBox(varargin)
% TTL_WAV_vs_TTLBox  (DECLUSTERED / student-style)
% -------------------------------------------------------------------------
% App-safe wrapper to compute TTL sync mapping (WAV -> TTLBox).
%
% Mapping model:
%   t_TTLBox = a * t_audio + b
%
% This function is meant to be called by the app button "Compute TTL sync".
% It delegates the heavy work to:
%   TTL_WAV_vs_TTLBox_run.m
%
% -------------------------------------------------------------------------
% CALL PATTERNS
% -------------------------------------------------------------------------
% 1) Non-interactive (recommended for apps / scripts)
%   out = TTL_WAV_vs_TTLBox(wavFile, ttlboxCsv, outDir);
%
% 2) Non-interactive with options
%   out = TTL_WAV_vs_TTLBox(wavFile, ttlboxCsv, outDir, ...
%        'Verbose', false, ...
%        'ReturnLog', true, ...
%        'Params', struct('map_matchTolSec',0.20,'wav_chunkSec',180));
%
% 3) Interactive (uses file pickers)
%   out = TTL_WAV_vs_TTLBox('Interactive', true);
%
% -------------------------------------------------------------------------
% OUTPUT (struct)
%   out.a, out.b                 mapping coefficients
%   out.delay_b_sec              same as out.b
%   out.t_audio_at_ttlbox0_sec   -b/a
%   out.qc                       quality control numbers (if available)
%   out.files                    deliverable paths from *_run
%   out.log                      captured command-window text (optional)
%   out.raw                      full raw output from *_run
%   out.wavFile / out.ttlboxRawFile / out.outDir
% -------------------------------------------------------------------------

%% -------------------- 1) Defaults --------------------
wavFile       = "";
ttlboxRawFile = "";
outDir        = "";

opts = struct();
opts.Interactive = false;
opts.Verbose     = true;

% App convenience
opts.MakeOutDir  = true;

% Log capture/return
opts.CaptureLog  = true;
opts.ReturnLog   = true;

% Overrides forwarded into TTL_WAV_vs_TTLBox_run (fields must match its P struct)
opts.Params      = struct();

%% -------------------- 2) Read positional args if present --------------------
% We accept up to 3 positional inputs:
%   (wavFile, ttlboxCsv, outDir)
% Everything else is Name-Value.
[nv, wavFile, ttlboxRawFile, outDir] = localReadPositional(varargin, wavFile, ttlboxRawFile, outDir);

%% -------------------- 3) Parse Name-Value options (simple loop) --------------------
opts = localParseNameValue(nv, opts);

%% -------------------- 4) Interactive pickers if requested --------------------
if opts.Interactive
    if strlength(wavFile) == 0
        [fW, pW] = uigetfile({'*.wav;*.WAV','WAV files (*.wav)'}, 'Select TTL WAV file');
        if isequal(fW,0)
            error('TTL_WAV_vs_TTLBox:Canceled','No WAV selected.');
        end
        wavFile = string(fullfile(pW,fW));
    end

    if strlength(ttlboxRawFile) == 0
        [fB, pB] = uigetfile({'*.csv;*.CSV','CSV files (*.csv)'}, 'Select TTLBox RAW CSV (Box15/16)');
        if isequal(fB,0)
            error('TTL_WAV_vs_TTLBox:Canceled','No TTLBox CSV selected.');
        end
        ttlboxRawFile = string(fullfile(pB,fB));
    end

    if strlength(outDir) == 0
        startDir = fileparts(wavFile);
        chosen = uigetdir(startDir, 'Select output folder');
        if isequal(chosen,0)
            error('TTL_WAV_vs_TTLBox:Canceled','No output folder selected.');
        end
        outDir = string(chosen);
    end
end

%% -------------------- 5) Validate inputs (non-interactive safety) --------------------
if ~opts.Interactive
    if strlength(wavFile) == 0 || ~isfile(wavFile)
        error('TTL_WAV_vs_TTLBox:MissingWav', 'wavFile is missing or not found.');
    end
    if strlength(ttlboxRawFile) == 0 || ~isfile(ttlboxRawFile)
        error('TTL_WAV_vs_TTLBox:MissingTTLBox', 'ttlboxRawFile is missing or not found.');
    end
    if strlength(outDir) == 0
        error('TTL_WAV_vs_TTLBox:MissingOutDir', 'outDir is required in non-interactive mode.');
    end
end

% Create output folder if needed
if strlength(outDir) > 0 && ~isfolder(outDir)
    if opts.MakeOutDir
        mkdir(outDir);
    else
        error('TTL_WAV_vs_TTLBox:OutDirNotFound', 'outDir does not exist: %s', outDir);
    end
end

%% -------------------- 6) Call underlying run function --------------------
% Convert opts.Params struct into Name-Value pairs
paramPairs = localStructToPairs(opts.Params);

logText = '';
rawOut  = struct();

try
    if opts.CaptureLog
        % Capture everything printed by *_run (useful for app log panel)
        logText = evalc('rawOut = TTL_WAV_vs_TTLBox_run(wavFile, ttlboxRawFile, outDir, paramPairs{:});');
    else
        rawOut  = TTL_WAV_vs_TTLBox_run(wavFile, ttlboxRawFile, outDir, paramPairs{:});
    end
catch ME
    ME2 = MException('TTL_WAV_vs_TTLBox:RunFailed', 'TTL sync mapping failed: %s', ME.message);
    ME2 = ME2.addCause(ME);
    throw(ME2);
end

% Echo captured log to command window if requested
if opts.Verbose && opts.CaptureLog && ~isempty(logText)
    fprintf('%s', logText);
end

%% -------------------- 7) Build compact output struct for the App --------------------
out = struct();
out.raw = rawOut;

% Mapping coefficients
if isfield(rawOut,'mapping')
    m = rawOut.mapping;

    out.a = localGetField(m,'a',NaN);
    out.b = localGetField(m,'b',NaN);

    out.delay_b_sec = out.b;

    if ~isnan(out.a) && out.a ~= 0
        out.t_audio_at_ttlbox0_sec = -out.b / out.a;
    else
        out.t_audio_at_ttlbox0_sec = NaN;
    end

    % QC bundle (only if present)
    qc = struct();
    qc.matched_audio      = localGetField(m,'matched_audio',NaN);
    qc.total_audio        = localGetField(m,'total_audio',NaN);
    qc.total_ttlbox       = localGetField(m,'total_ttlbox',NaN);
    qc.offset_median_s    = localGetField(m,'offset_median_s',NaN);
    qc.resid_median_abs_s = localGetField(m,'resid_median_abs_s',NaN);
    qc.resid_p95_abs_s    = localGetField(m,'resid_p95_abs_s',NaN);
    out.qc = qc;
else
    out.a = NaN;
    out.b = NaN;
    out.delay_b_sec = NaN;
    out.t_audio_at_ttlbox0_sec = NaN;
    out.qc = struct();
end

% Deliverables
if isfield(rawOut,'files')
    out.files = rawOut.files;
else
    out.files = struct();
end

% Optional captured log
if opts.ReturnLog
    out.log = logText;
end

% Useful for app display (always as char)
out.wavFile       = char(wavFile);
out.ttlboxRawFile = char(ttlboxRawFile);
out.outDir        = char(outDir);

end

%% ========================= LOCAL HELPERS =========================

function [nv, wavFile, ttlboxRawFile, outDir] = localReadPositional(allArgs, wavFile, ttlboxRawFile, outDir)
% Reads up to 3 positional arguments (wav, csv, outDir) if they are present.
% Everything else is returned as nv (Name-Value list).

nv = allArgs;

% List of known option names
optNames = ["interactive","verbose","makeoutdir","capturelog","returnlog","params"];

% Positional #1: wavFile
if ~isempty(nv)
    a1 = nv{1};
    if localLooksLikePositional(a1, optNames)
        wavFile = string(a1);
        nv(1) = [];
    end
end

% Positional #2: ttlboxRawFile
if ~isempty(nv)
    a2 = nv{1};
    if localLooksLikePositional(a2, optNames)
        ttlboxRawFile = string(a2);
        nv(1) = [];
    end
end

% Positional #3: outDir
if ~isempty(nv)
    a3 = nv{1};
    if localLooksLikePositional(a3, optNames)
        outDir = string(a3);
        nv(1) = [];
    end
end
end

function tf = localLooksLikePositional(x, optNames)
% True if x should be treated as a positional value, not an option name.

tf = false;

if ~(ischar(x) || isstring(x))
    return;
end

s = lower(strtrim(string(x)));
if strlength(s) == 0
    return;
end

% If it equals a known option name, it is NOT positional
if any(s == optNames)
    return;
end

% If it looks like a file path or folder, treat as positional
% (This is permissive; downstream validation will catch mistakes.)
tf = true;
end

function opts = localParseNameValue(nv, opts)
% Beginner-style Name-Value parsing.

if isempty(nv)
    return;
end

if mod(numel(nv),2) ~= 0
    error('TTL_WAV_vs_TTLBox:BadArgs', 'Name-Value inputs must come in pairs.');
end

k = 1;
while k <= numel(nv)
    name  = nv{k};
    value = nv{k+1};

    if ~(ischar(name) || isstring(name))
        error('TTL_WAV_vs_TTLBox:BadArgs', 'Option name at position %d must be text.', k);
    end

    key = lower(string(name));

    if key == "interactive"
        opts.Interactive = logical(value) && isscalar(value);
    elseif key == "verbose"
        opts.Verbose = logical(value) && isscalar(value);
    elseif key == "makeoutdir"
        opts.MakeOutDir = logical(value) && isscalar(value);
    elseif key == "capturelog"
        opts.CaptureLog = logical(value) && isscalar(value);
    elseif key == "returnlog"
        opts.ReturnLog = logical(value) && isscalar(value);
    elseif key == "params"
        if isempty(value)
            opts.Params = struct();
        elseif isstruct(value)
            opts.Params = value;
        else
            error('TTL_WAV_vs_TTLBox:BadParams', '''Params'' must be a struct or empty.');
        end
    else
        error('TTL_WAV_vs_TTLBox:UnknownOption', 'Unknown option: %s', key);
    end

    k = k + 2;
end
end

function pairs = localStructToPairs(S)
pairs = {};
if isempty(S)
    return;
end

if ~isstruct(S)
    return;
end

fn = fieldnames(S);
for i = 1:numel(fn)
    pairs(end+1:end+2) = {fn{i}, S.(fn{i})}; %#ok<AGROW>
end
end

function v = localGetField(S, fieldName, defaultVal)
if isstruct(S) && isfield(S, fieldName)
    v = S.(fieldName);
else
    v = defaultVal;
end
end
