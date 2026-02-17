function out = TTL_WAV_vs_TTLBox_run(wavFile, ttlboxRawFile, outDir, varargin)
%TTL_WAV_vs_TTLBox_run  TTL WAV vs TTLBox sync mapping (PASS 2: extra-declustered + heavy comments)
%
%   out = TTL_WAV_vs_TTLBox_run(wavFile, ttlboxRawFile, outDir)
%
% INPUTS
%   wavFile       : .wav file that contains audio-encoded TTL edges (audio timebase)
%   ttlboxRawFile : TTL Box15/16 RAW .csv file (TTLBox timebase)
%   outDir        : output folder for the Excel files
%
% OUTPUT (out.files)
%   *_TTLBox_EVENTS.xlsx
%   *_WAV_vs_TTLBox_ALIGNMENT.xlsx
%   *_SYNC_MAPPING.xlsx
%
% MAPPING CONVENTION USED IN THE WHOLE PROJECT
%   t_TTLBox = a * t_audio + b
%
% DELIVERABLE FILES CREATED BY THIS RUNNER
%   1) *_TTLBox_EVENTS.xlsx
%        - Sheet 'PULSES_decoded' : decoded TTL pulses from TTLBox time base
%        - Sheet 'COUNTS'         : simple counts by pulse label
%   2) *_WAV_vs_TTLBox_ALIGNMENT.xlsx
%        - Single sheet with WAV-detected candidates + matched TTLBox events
%   3) *_SYNC_MAPPING.xlsx
%        - Sheet 'sync_mapping' with mapping parameters
%        - This file is used later by USV_Timeline_shift_run.m
%
% IMPORTANT SAFETY NOTE
%   This pass does NOT change the algorithm.
%   Changes are only readability: extra comments and clearer intermediate variables.

%
% NOTE
%   This file is intentionally written in a step-by-step (beginner) style.
%   It avoids overly compact one-liners and keeps the flow explicit.

%% -------------------- 0) Defaults --------------------
P = struct();

% WAV detection (EDGEPAIR)
P.wav_chunkSec         = 180;     % seconds per chunk to read (RAM-safe)
P.wav_overlapSec       = 1.0;     % seconds overlap between chunks
P.wav_smoothMs         = 0.08;    % smoothing on abs(diff(x)) (ms)
P.wav_peakThrMAD       = 10;      % threshold = median + k*MAD
P.wav_minPeakDistMs    = 6;       % de-dup peaks (ms)
P.wav_minSepMs         = 5;       % pair separation min (ms)
P.wav_maxSepMs         = 120;     % pair separation max (ms)
P.wav_matchTolMs       = 8;       % tolerance (ms) around [20 40 60 80]
P.wav_clusterRefracSec = 0.10;    % refractory window to de-duplicate events (sec)

% TTLBox decoding
P.expectedMs    = [20 40 60 80];
P.ttl_tolMs     = 4;
P.ttl_minDurMs  = 5;
P.ttl_maxDurMs  = 200;

% Mapping / alignment
P.map_histBinSec  = 0.02;        % histogram bin width for coarse offset (sec)
P.map_matchTolSec = 0.25;        % match tolerance for greedy matching (sec)

%% -------------------- 1) Handle inputs and overrides --------------------
if nargin < 1, wavFile = ''; end
if nargin < 2, ttlboxRawFile = ''; end
if nargin < 3, outDir = ''; end

% Apply overrides like: 'map_matchTolSec', 0.2
if ~isempty(varargin)
    P = applyOverrides(P, varargin);
end

% Make sure these are text
wavFile       = char(string(wavFile));
ttlboxRawFile = char(string(ttlboxRawFile));
outDir        = char(string(outDir));

%% -------------------- 2) Pick files if missing --------------------
[wavFile, wavNameForBase] = pickWavIfNeeded(wavFile);
[ttlboxRawFile, boxNameForBase] = pickTTLBoxIfNeeded(ttlboxRawFile);

% Output directory: default to WAV folder if not provided
if isempty(outDir)
    outDir = fileparts(wavFile);
end
if ~isfolder(outDir)
    mkdir(outDir);
end

%% -------------------- 3) Define output filenames --------------------
wavBase = fileBaseNoExt(wavNameForBase);
boxBase = fileBaseNoExt(boxNameForBase);

outTTLBoxXLSX = fullfile(outDir, [wavBase '_' boxBase '_TTLBox_EVENTS.xlsx']);
outAlignXLSX  = fullfile(outDir, [wavBase '_' boxBase '_WAV_vs_TTLBox_ALIGNMENT.xlsx']);
outSyncXLSX   = fullfile(outDir, [wavBase '_' boxBase '_SYNC_MAPPING.xlsx']);

%% -------------------- 4) Read WAV info (basic sanity) --------------------
% We only read metadata here (sample rate, duration) to know how big the file is.
% We do NOT load the full WAV into memory at once.
% Later, detectTTLwav_EDGEPAIR() reads the WAV in chunks (RAM-safe).
info = audioinfo(wavFile);
fs   = info.SampleRate;
N    = info.TotalSamples;
C    = info.NumChannels;

fprintf('\nWAV: %s\n', wavFile);
fprintf('Fs: %.0f Hz | Channels: %d | Duration: %.2f min\n', fs, C, (N/fs/60));
if C < 1
    error('WAV has no channels.');
end
ch = 1; % fixed to channel 1 (consistent with previous versions)

fprintf('TTLBox RAW: %s\n', ttlboxRawFile);
fprintf('Output dir: %s\n', outDir);

%% -------------------- 5) Decode TTLBox RAW -> pulses --------------------
% The TTLBox CSV contains edge times. We convert edges into pulse durations.
% Those durations are then labeled as 20/40/60/80 ms (Food/Drug markers etc).
% The output table TBpulses is our 'ground truth' time base for alignment.
% TBpulses is the main table we need (t_start_s is the TTLBox time base).
[~, TBpulses, ttlMeta] = decodeTTLBox_RAW_and_PULSES(ttlboxRawFile, P);

% Write TTLBox deliverable (2 sheets: PULSES_decoded + COUNTS)
if safeIsFile(outTTLBoxXLSX)
    delete(outTTLBoxXLSX);
end

safeWriteSheet(outTTLBoxXLSX, TBpulses, 'PULSES_decoded');

% Counts (beginner style: loop)
Tcounts = buildCountsTable(TBpulses);
safeWriteSheet(outTTLBoxXLSX, Tcounts, 'COUNTS');

fprintf('Wrote TTLBox thesis file: %s\n', outTTLBoxXLSX);

tBox = TBpulses.t_start_s;

%% -------------------- 6) Detect TTL-like events in WAV --------------------
% The WAV contains an audio-coded TTL signal. We detect events by:
%   1) reading audio in chunks
%   2) computing abs(diff(audio)) to highlight edges
%   3) finding peaks and pairing them into pulses
% The result TW has candidate pulse start times in AUDIO time base.
TW = detectTTLwav_EDGEPAIR(wavFile, fs, N, ch, P);
tAud = TW.t_start_s;

%% -------------------- 7) Estimate mapping t_TTLBox = a*t_audio + b --------------------
% We estimate a linear mapping between time bases.
% Step 1: coarse offset using a histogram of time differences.
% Step 2: greedy match within tolerance.
% Step 3: linear fit (a,b) on matched pairs.
% (Beginner-friendly) pull parameters into named variables
histBinSec  = P.map_histBinSec;      % coarse offset histogram bin width
matchTolSec = P.map_matchTolSec;     % greedy match tolerance
% Estimate mapping between AUDIO time and TTLBox time
mapping = estimateMapping(tAud, tBox, histBinSec, matchTolSec);


%% -------------------- 8) Write ALIGNMENT deliverable --------------------
% Single sheet ("alignment") with all WAV candidates; TTLBox columns filled only for matched pairs.
if safeIsFile(outAlignXLSX)
    delete(outAlignXLSX);
end
writeAlignmentSingleSheet(outAlignXLSX, TW, TBpulses, mapping, ttlMeta);
fprintf('Wrote alignment thesis file: %s\n', outAlignXLSX);

%% -------------------- 9) Write SYNC_MAPPING deliverable --------------------
% This is the only file the later shift step really needs.
% The mapping is always saved in the convention:
%   t_TTLBox = a * t_audio + b
% We keep only ONE mapping file (xlsx), sheet: 'sync_mapping'
cleanupOldMappingArtifacts(outSyncXLSX);

if safeIsFile(outSyncXLSX)
    delete(outSyncXLSX);
end

Tsync = buildSyncMappingTable(mapping, P);
safeWriteSheet(outSyncXLSX, Tsync, 'sync_mapping');

fprintf('Wrote SYNC mapping Excel (single file): %s\n', outSyncXLSX);

%% -------------------- 10) Print short summary --------------------
fprintf('\n==================== RESULT SUMMARY ====================\n');
fprintf('TTLBox markerMode: %s\n', char(string(ttlMeta.markerMode)));
fprintf('TTLBox chosen source: %s\n', char(string(ttlMeta.sourceKey)));
fprintf('TTLBox pulses kept: %d\n', height(TBpulses));
fprintf('WAV detections kept: %d\n\n', height(TW));

fprintf('Matched: %d / audio %d / TTLBox %d (tol=%.3fs)\n', ...
    mapping.matched_audio, mapping.total_audio, mapping.total_ttlbox, P.map_matchTolSec);

fprintf('Mapping: t_TTLBox ~= a*t_Audio + b\n');
fprintf('  a = %.6f\n', mapping.a);
fprintf('  b = %.3f s\n', mapping.b);
fprintf('Derived: t_audio_at_ttlbox0 = -b/a = %.3f s\n', -mapping.b/mapping.a);
fprintf('QC: residual |median| = %.3f s | p95 = %.3f s\n', mapping.resid_median_abs_s, mapping.resid_p95_abs_s);
fprintf('========================================================\n');

%% -------------------- 11) Pack outputs --------------------
out = struct();
out.wavFile = wavFile;
out.ttlboxRawFile = ttlboxRawFile;
out.outDir = outDir;

out.files = struct();
out.files.TTLBox_EVENTS           = outTTLBoxXLSX;
out.files.WAV_vs_TTLBox_ALIGNMENT = outAlignXLSX;
out.files.SYNC_MAPPING            = outSyncXLSX;

% Backwards-compatible aliases used by the Master App:
out.files.TTLBoxXLSX = outTTLBoxXLSX;
out.files.AlignXLSX  = outAlignXLSX;
out.files.SyncXLSX   = outSyncXLSX;

out.mapping = mapping;
out.ttlMeta = ttlMeta;
out.P = P;

end

%% ========================================================================
% Helper: apply name/value overrides
function P = applyOverrides(P, args)
% applyOverrides
%   Reads Name/Value overrides and applies them to struct P.
%   Example: TTL_WAV_vs_TTLBox_run(..., 'map_matchTolSec', 0.2)
%   We only allow keys that already exist in P to avoid silent typos.
    if mod(numel(args),2) ~= 0
        error('Overrides must be name/value pairs.');
    end

    i = 1;
    while i <= numel(args)
        key = char(string(args{i}));
        val = args{i+1};

        if isfield(P, key)
            P.(key) = val;
        else
            error('Unknown parameter: %s', key);
        end

        i = i + 2;
    end
end

%% ========================================================================
% Helper: pick input WAV if missing
function [wavFile, wavNameForBase] = pickWavIfNeeded(wavFile)

    wavNameForBase = '';

    if ~safeIsFile(wavFile)
        [fW, pW] = uigetfile({'*.wav;*.WAV','WAV files (*.wav)'; '*.*','All files'}, 'Select TTL WAV file');
        if isequal(fW,0)
            error('Canceled.');
        end
        wavFile = fullfile(pW, fW);
        wavNameForBase = fW;
    else
        [~, f0, e0] = fileparts(wavFile);
        wavNameForBase = [f0 e0];
    end
end

%% ========================================================================
% Helper: pick TTLBox CSV if missing
function [boxFile, boxNameForBase] = pickTTLBoxIfNeeded(boxFile)

    boxNameForBase = '';

    if ~safeIsFile(boxFile)
        [fB, pB] = uigetfile({'*.csv','CSV files (*.csv)'; '*.*','All files'}, 'Select TTL Box RAW CSV (TTL Box15/16)');
        if isequal(fB,0)
            error('Canceled.');
        end
        boxFile = fullfile(pB, fB);
        boxNameForBase = fB;
    else
        [~, f1, e1] = fileparts(boxFile);
        boxNameForBase = [f1 e1];
    end
end

%% ========================================================================
% Helper: base name without extension
function b = fileBaseNoExt(fname)
    [~, b, ~] = fileparts(fname);
end

%% ========================================================================
function tf = safeIsFile(f)
    % Avoids MATLAB errors like isfile(0) / isfile("").
    tf = false;

    if isempty(f)
        return;
    end
    if isnumeric(f)
        return;
    end

    f = char(string(f));
    if isempty(f)
        return;
    end

    tf = isfile(f);
end

%% ========================================================================
function safeWriteSheet(xlsxFile, T, sheetName)
    % Writes a table to a specific sheet. Tries both calling styles for compatibility.
    try
        writetable(T, xlsxFile, 'Sheet', sheetName);
    catch
        writetable(T, xlsxFile, 'FileType','spreadsheet', 'Sheet', sheetName);
    end
end

%% ========================================================================
function Tcounts = buildCountsTable(TBpulses)
    % Builds {Event, Count} table without accumarray (beginner style).

    if isempty(TBpulses) || height(TBpulses) == 0
        Tcounts = table(strings(0,1), zeros(0,1), 'VariableNames', {'Event','Count'});
        return;
    end

    events = string(TBpulses.Event);
    uniqueEvents = unique(events);

    cnt = zeros(numel(uniqueEvents), 1);
    for i = 1:numel(uniqueEvents)
        cnt(i) = sum(events == uniqueEvents(i));
    end

    Tcounts = table(uniqueEvents, cnt, 'VariableNames', {'Event','Count'});
end

%% ========================================================================
function cleanupOldMappingArtifacts(outSyncXLSX)
    oldSyncCSV = strrep(outSyncXLSX, '.xlsx', '.csv');
    oldSyncMAT = strrep(outSyncXLSX, '.xlsx', '.mat');
    oldSyncTXT = strrep(outSyncXLSX, '_SYNC_MAPPING.xlsx', '_SYNC_MAPPING_README.txt');

    if safeIsFile(oldSyncCSV), delete(oldSyncCSV); end
    if safeIsFile(oldSyncMAT), delete(oldSyncMAT); end
    if safeIsFile(oldSyncTXT), delete(oldSyncTXT); end
end

%% ========================================================================
function Tsync = buildSyncMappingTable(mapping, P)
    % Creates a simple Field/Value sheet.

    fields = strings(0,1);
    values = strings(0,1);

    fields(end+1,1) = "Primary mapping";
    values(end+1,1) = "t_TTLBox = a*t_audio + b";

    fields(end+1,1) = "a (drift)";
    values(end+1,1) = string(sprintf('%.9f', mapping.a));

    fields(end+1,1) = "b (s)";
    values(end+1,1) = string(sprintf('%.6f', mapping.b));

    fields(end+1,1) = "t_ttlbox_at_audio0_s (equals b)";
    values(end+1,1) = string(sprintf('%.6f', mapping.b));

    fields(end+1,1) = "t_audio_at_ttlbox0_s (= -b/a)";
    values(end+1,1) = string(sprintf('%.6f', -mapping.b/mapping.a));

    fields(end+1,1) = "";
    values(end+1,1) = "";

    fields(end+1,1) = "Matching / QC";
    values(end+1,1) = "";

    fields(end+1,1) = "matched_audio";
    values(end+1,1) = string(mapping.matched_audio);

    fields(end+1,1) = "total_audio_candidates";
    values(end+1,1) = string(mapping.total_audio);

    fields(end+1,1) = "total_ttlbox_pulses";
    values(end+1,1) = string(mapping.total_ttlbox);

    fields(end+1,1) = "matchTolSec";
    values(end+1,1) = string(sprintf('%.6f', P.map_matchTolSec));

    fields(end+1,1) = "offset_median_s";
    values(end+1,1) = string(sprintf('%.6f', mapping.offset_median_s));

    fields(end+1,1) = "resid_median_abs_s";
    values(end+1,1) = string(sprintf('%.6f', mapping.resid_median_abs_s));

    fields(end+1,1) = "resid_p95_abs_s";
    values(end+1,1) = string(sprintf('%.6f', mapping.resid_p95_abs_s));

    Tsync = table(fields, values, 'VariableNames', {'Field','Value'});
end

%% ========================================================================
function writeAlignmentSingleSheet(xlsxFile, TW, TBpulses, mapping, ttlMeta)
    % Builds the single-sheet alignment deliverable.

    sheetName = 'alignment';

    headers = { ...
        'WAV Event index','wav_start_s','wav_end_s', ...
        'BOX Event index','box_start_s','box_end_s', ...
        'TTL_Event_type','TTLBox_code_ms','predicted_minus_actual_s', ...
        'ttlbox_minus_wav_s','ttlbox_raw_t0_abs_s'};

    nW = height(TW);
    if nW == 0
        writecell(headers, xlsxFile, 'Sheet', sheetName);
        return;
    end

    wavStartRaw = TW.t_start_s(:);
    wavEndRaw   = TW.t_end_s(:);

    wavStart = round(wavStartRaw, 6);
    wavEnd   = round(wavEndRaw, 6);

    % Pre-allocate
    boxIdx   = nan(nW,1);
    boxStart = nan(nW,1);
    boxEnd   = nan(nW,1);
    evtType  = strings(nW,1);
    codeMs   = nan(nW,1);

    predMinusActual = nan(nW,1);
    ttlboxMinusWav  = nan(nW,1);
    ttlboxRawT0Abs  = nan(nW,1);

    pairsA = mapping.pairs_audio_idx(:);
    pairsB = mapping.pairs_ttlbox_idx(:);

    if ~isempty(pairsA)
        for k = 1:numel(pairsA)
            ai = pairsA(k);
            bi = pairsB(k);

            boxIdx(ai)   = TBpulses.EventIndex(bi);
            boxStart(ai) = TBpulses.t_start_s(bi);
            boxEnd(ai)   = TBpulses.t_end_s(bi);
            evtType(ai)  = TBpulses.Event(bi);
            codeMs(ai)   = TBpulses.code_ms(bi);

            pred = mapping.a * wavStartRaw(ai) + mapping.b;
            predMinusActual(ai) = pred - boxStart(ai);

            ttlboxMinusWav(ai) = boxStart(ai) - wavStartRaw(ai);
            ttlboxRawT0Abs(ai) = ttlMeta.t0_abs;
        end
    end

    % Round
    boxStart = round(boxStart, 6);
    boxEnd   = round(boxEnd, 6);
    predMinusActual = round(predMinusActual, 6);
    ttlboxMinusWav  = round(ttlboxMinusWav, 6);
    ttlboxRawT0Abs  = round(ttlboxRawT0Abs, 6);

    % Build output cell data (row-by-row)
    data = cell(nW, numel(headers));

    for i = 1:nW
        data{i,1} = i;
        data{i,2} = wavStart(i);
        data{i,3} = wavEnd(i);

        if ~isnan(boxIdx(i))
            data{i,4}  = boxIdx(i);
            data{i,5}  = boxStart(i);
            data{i,6}  = boxEnd(i);
            data{i,7}  = char(evtType(i));
            data{i,8}  = codeMs(i);
            data{i,9}  = predMinusActual(i);
            data{i,10} = ttlboxMinusWav(i);
            data{i,11} = ttlboxRawT0Abs(i);
        else
            data{i,4}  = [];
            data{i,5}  = [];
            data{i,6}  = [];
            data{i,7}  = [];
            data{i,8}  = [];
            data{i,9}  = [];
            data{i,10} = [];
            data{i,11} = [];
        end
    end

    writecell([headers; data], xlsxFile, 'Sheet', sheetName);
end

%% ========================================================================
function [TBrawN, TBpulses, meta] = decodeTTLBox_RAW_and_PULSES(csvFile, P)
    % Reads TTLBox RAW CSV and chooses the best source (Input+CH) automatically.

    Traw = readtable(csvFile, 'ReadVariableNames', false);

    if width(Traw) < 4
        error('TTLBox RAW file does not have expected columns (need at least 4).');
    end

    inputName = string(Traw{:,1});
    chNum     = Traw{:,2};
    stateRaw  = string(Traw{:,3});
    tAbs      = double(Traw{:,4});

    srcKey = inputName + "_CH" + string(chNum);
    uKeys = unique(srcKey);

    bestCount = -inf;

    bestRaw = table();
    bestPulses = table();
    bestMeta = struct();

    for k = 1:numel(uKeys)
        key = uKeys(k);
        m = (srcKey == key);

        tt = tAbs(m);
        ss = stateRaw(m);

        if numel(tt) < 5
            continue;
        end

        t0 = tt(1);
        tn = tt - t0;

        isHigh = parseHighLow(ss);

        TBraw = table((1:numel(tt)).', ss(:), isHigh(:), tt(:), tn(:), ...
            'VariableNames', {'RawIndex','StateStr','IsHigh','t_abs_s','t_norm_s'});

        Ptab_low  = decodePulses_fromTransitions(tn, isHigh, "LOW",  P);
        Ptab_high = decodePulses_fromTransitions(tn, isHigh, "HIGH", P);

        if height(Ptab_low) >= height(Ptab_high)
            Pbest = Ptab_low;
            pol = "LOW";
        else
            Pbest = Ptab_high;
            pol = "HIGH";
        end

        c = height(Pbest);
        if c > bestCount
            bestCount = c;
            bestRaw = TBraw;
            bestPulses = Pbest;

            bestMeta.sourceKey = key;
            bestMeta.markerMode = "FIRST_RAW_ROW";
            bestMeta.polarity = pol;
            bestMeta.t0_abs = t0;
        end
    end

    if bestCount < 0
        error('No usable source found in TTLBox RAW.');
    end

    TBrawN = bestRaw;
    TBpulses = bestPulses;
    meta = bestMeta;

    TBrawN.source = repmat(string(meta.sourceKey), height(TBrawN), 1);
    TBrawN = movevars(TBrawN, "source", "Before", 1);

    TBpulses.source = repmat(string(meta.sourceKey), height(TBpulses), 1);
    TBpulses = movevars(TBpulses, "source", "Before", 1);
end

function isHigh = parseHighLow(stateStr)
    isHigh = false(size(stateStr));

    isHigh(strcmpi(stateStr,"True"))  = true;
    isHigh(strcmpi(stateStr,"False")) = false;

    if all(~isHigh)
        v = str2double(stateStr);
        if any(~isnan(v))
            isHigh = v > 0.5;
        end
    end
end

function Ptab = decodePulses_fromTransitions(tn, isHigh, whichPulse, P)
    d = diff(isHigh);

    if whichPulse == "LOW"
        startIdx = find(d == -1) + 1;
        endIdx   = find(d == +1) + 1;
    else
        startIdx = find(d == +1) + 1;
        endIdx   = find(d == -1) + 1;
    end

    t_start = zeros(0,1);
    t_end   = zeros(0,1);
    dur_ms  = zeros(0,1);

    ePtr = 1;

    for i = 1:numel(startIdx)
        s = startIdx(i);

        while ePtr <= numel(endIdx) && endIdx(ePtr) <= s
            ePtr = ePtr + 1;
        end
        if ePtr > numel(endIdx)
            break;
        end

        e = endIdx(ePtr);

        ts = tn(s);
        te = tn(e);
        dm = (te - ts) * 1000;

        if dm >= P.ttl_minDurMs && dm <= P.ttl_maxDurMs
            bestDiff = min(abs(P.expectedMs - dm));
            if bestDiff <= P.ttl_tolMs
                t_start(end+1,1) = ts; %#ok<AGROW>
                t_end(end+1,1)   = te; %#ok<AGROW>
                dur_ms(end+1,1)  = dm; %#ok<AGROW>
            end
        end

        ePtr = ePtr + 1;
    end

    n = numel(t_start);
    code_ms = zeros(n,1);
    Event   = strings(n,1);

    for i = 1:n
        [~, idx] = min(abs(P.expectedMs - dur_ms(i)));
        code_ms(i) = P.expectedMs(idx);
        Event(i) = codeToLabel(code_ms(i));
    end

    Ptab = table((1:n).', t_start, t_end, dur_ms, code_ms, Event, ...
        'VariableNames', {'EventIndex','t_start_s','t_end_s','duration_ms','code_ms','Event'});
end

function name = codeToLabel(code_ms)
    switch code_ms
        case 20
            name = "LeftPress_20ms";
        case 40
            name = "RightPress_40ms";
        case 60
            name = "DrugReward_60ms";
        case 80
            name = "FoodReward_80ms";
        otherwise
            name = "Event_" + string(code_ms) + "ms";
    end
end

function TW = detectTTLwav_EDGEPAIR(wavFile, fs, N, ch, P)
    chunkSamples   = max(1, round(P.wav_chunkSec * fs));
    overlapSamples = max(0, round(P.wav_overlapSec * fs));

    smoothSamples   = max(1, round((P.wav_smoothMs/1000) * fs));
    minPeakDistSamp = max(1, round((P.wav_minPeakDistMs/1000) * fs));
    minSepSamp      = max(1, round((P.wav_minSepMs/1000) * fs));
    maxSepSamp      = max(1, round((P.wav_maxSepMs/1000) * fs));

    allStart = zeros(0,1,'uint64');
    allEnd   = zeros(0,1,'uint64');
    allDTms  = zeros(0,1);
    allStr   = zeros(0,1);

    fprintf('\nDetecting TTL pattern in WAV (EDGEPAIR) in %.1f sec chunks...\n', P.wav_chunkSec);

    chunkStart = 1;
    chunkIdx = 0;

    while chunkStart <= N
        chunkIdx = chunkIdx + 1;

        mainStart = chunkStart;
        mainEnd   = min(N, chunkStart + chunkSamples - 1);

        readStart = max(1, mainStart - overlapSamples);
        readEnd   = min(N, mainEnd + overlapSamples);

        x = audioread(wavFile, [readStart readEnd]);
        x = x(:, ch);
        x = x - mean(x, 'omitnan');

        dx  = abs([0; diff(x)]);
        env = movmean(dx, smoothSamples);

        medv = median(env);
        madv = median(abs(env - medv)) + eps;
        thr  = medv + P.wav_peakThrMAD * madv;

        peaks = localPeaks(env, thr, minPeakDistSamp);

        if numel(peaks) >= 2
            used = false(size(peaks));

            for i = 1:numel(peaks)
                if used(i)
                    continue;
                end

                pi = peaks(i);

                cand = find(peaks > (pi + minSepSamp) & peaks < (pi + maxSepSamp) & ~used);
                if isempty(cand)
                    continue;
                end

                dt_ms_all = (peaks(cand) - pi) / fs * 1000;

                bestDist = inf;
                bestJ = -1;

                for kk = 1:numel(cand)
                    dt = dt_ms_all(kk);
                    dist = min(abs(P.expectedMs - dt));

                    if dist < bestDist
                        bestDist = dist;
                        bestJ = cand(kk);
                    end
                end

                if bestDist > P.wav_matchTolMs
                    continue;
                end

                pj = peaks(bestJ);

                used(i) = true;
                used(bestJ) = true;

                allStart(end+1,1) = uint64(pi + readStart - 1); %#ok<AGROW>
                allEnd(end+1,1)   = uint64(pj + readStart - 1); %#ok<AGROW>
                allDTms(end+1,1)  = (pj - pi)/fs*1000;          %#ok<AGROW>
                allStr(end+1,1)   = env(pi) + env(pj);          %#ok<AGROW>
            end
        end

        if mod(chunkIdx, 10) == 0
            fprintf('Chunk %d | raw events: %d | %.1f%%\n', chunkIdx, numel(allStart), 100*double(mainEnd)/double(N));
        end

        chunkStart = mainEnd + 1;
    end

    if isempty(allStart)
        TW = table([],[],[],[],[],[], 'VariableNames', {'EventIndex','t_start_s','t_end_s','dt_ms','strength','sample_start','sample_end'});
        return;
    end

    tStart_s = double(allStart - 1) / fs;
    tEnd_s   = double(allEnd - 1) / fs;

    raw = table(tStart_s(:), tEnd_s(:), allDTms(:), allStr(:), double(allStart(:)), double(allEnd(:)), ...
        'VariableNames', {'t_start_s','t_end_s','dt_ms','strength','sample_start','sample_end'});

    raw = sortrows(raw, 't_start_s');

    % Dedup within refractory window, keep strongest
    refrac = P.wav_clusterRefracSec;
    keepIdx = false(height(raw),1);

    i = 1;
    while i <= height(raw)
        j = i;
        while j < height(raw) && (raw.t_start_s(j+1) - raw.t_start_s(i)) <= refrac
            j = j + 1;
        end

        [~, kbest] = max(raw.strength(i:j));
        keepIdx(i + kbest - 1) = true;

        i = j + 1;
    end

    TW = raw(keepIdx, :);
    TW.EventIndex = (1:height(TW)).';
    TW = movevars(TW, 'EventIndex', 'Before', 1);
end

function peaks = localPeaks(y, thr, minDist)
    if numel(y) < 3
        peaks = zeros(0,1);
        return;
    end

    isPk = (y(2:end-1) > y(1:end-2)) & (y(2:end-1) >= y(3:end)) & (y(2:end-1) >= thr);
    idx = find(isPk) + 1;

    if isempty(idx)
        peaks = zeros(0,1);
        return;
    end

    peaks = idx(1);

    for k = 2:numel(idx)
        if idx(k) - peaks(end) >= minDist
            peaks(end+1,1) = idx(k); %#ok<AGROW>
        else
            if y(idx(k)) > y(peaks(end))
                peaks(end) = idx(k);
            end
        end
    end
end

function mapping = estimateMapping(tAud, tBox, binSec, matchTolSec)
    mapping = struct();

    tAud = tAud(:);
    tBox = tBox(:);

    mapping.total_audio  = numel(tAud);
    mapping.total_ttlbox = numel(tBox);

    if isempty(tAud) || isempty(tBox)
        mapping.a = 1;
        mapping.b = NaN;

        mapping.offset_median_s = NaN;
        mapping.matched_audio = 0;

        mapping.pairs_audio_idx = [];
        mapping.pairs_ttlbox_idx = [];

        mapping.residual_s = [];
        mapping.resid_median_abs_s = NaN;
        mapping.resid_p95_abs_s = NaN;
        mapping.hist_peak_count = 0;
        return;
    end

    % Coarse offset by histogram of differences
    D = buildDifferenceVector(tAud, tBox);

    dMin = min(D);
    dMax = max(D);

    edges = (floor(dMin/binSec)*binSec) : binSec : (ceil(dMax/binSec)*binSec + binSec);
    if numel(edges) < 5
        edges = linspace(dMin, dMax, 200);
    end

    counts = histcounts(D, edges);
    [cmax, imax] = max(counts);

    b0 = (edges(imax) + edges(imax+1))/2;
    mapping.hist_peak_count = cmax;

    % Match with a=1, b=b0
    [pairsA, pairsB] = greedyMatch(tAud, tBox, 1, b0, matchTolSec);

    % Refine with linear fit if enough pairs
    if numel(pairsA) >= 8
        ta = tAud(pairsA);
        tb = tBox(pairsB);
        p = polyfit(ta, tb, 1);
        a = p(1);
        b = p(2);
    else
        a = 1;
        b = b0;
    end

    % Re-match
    [pairsA, pairsB] = greedyMatch(tAud, tBox, a, b, matchTolSec);

    ta = tAud(pairsA);
    tb = tBox(pairsB);

    resid = tb - (a*ta + b);

    mapping.a = a;
    mapping.b = b;

    mapping.pairs_audio_idx  = pairsA;
    mapping.pairs_ttlbox_idx = pairsB;

    mapping.residual_s = resid;
    mapping.matched_audio = numel(pairsA);

    off = tb - ta;
    mapping.offset_median_s = median(off);

    mapping.resid_median_abs_s = median(abs(resid));
    mapping.resid_p95_abs_s    = prctile(abs(resid), 95);
end

function D = buildDifferenceVector(tAud, tBox)
    if numel(tAud) * numel(tBox) > 2e6
        na = min(numel(tAud), 2000);
        nb = min(numel(tBox), 2000);

        ta = tAud(randperm(numel(tAud), na));
        tb = tBox(randperm(numel(tBox), nb));

        D = reshape(tb, [], 1) - reshape(ta, 1, []);
        D = D(:);
    else
        D = reshape(tBox, [], 1) - reshape(tAud, 1, []);
        D = D(:);
    end
end

function [pairsA, pairsB] = greedyMatch(tAud, tBox, a, b, tolSec)
    tPred = a*tAud + b;

    usedB = false(size(tBox));

    pairsA = zeros(0,1);
    pairsB = zeros(0,1);

    for i = 1:numel(tAud)
        [dmin, j] = min(abs(tBox - tPred(i)));

        if dmin <= tolSec && ~usedB(j)
            usedB(j) = true;

            pairsA(end+1,1) = i; %#ok<AGROW>
            pairsB(end+1,1) = j; %#ok<AGROW>
        end
    end
end
