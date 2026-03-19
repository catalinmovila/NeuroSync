function out = step2_ttl_sync_mapping(wavFile, ttlboxCsv, outDir)
% step2_ttl_sync_mapping  (DECLUSTERED / student-style)
% -------------------------------------------------------------------------
% PURPOSE
%   Wrapper used by the Master App.
%   Builds the audio->TTLBox sync mapping (a,b) and writes deliverables.
%
% INPUTS
%   wavFile    : TTL WAV file (audio-encoded TTL pulses)
%   ttlboxCsv  : TTLBox CSV file (hardware TTL log)
%   outDir     : output folder (optional; default = folder of wavFile)
%
% OUTPUT
%   out        : struct returned by TTL_WAV_vs_TTLBox_run
%                (contains mapping.a, mapping.b, files.SyncXLSX, etc.)
%
% NOTE
%   Heavy work is done in:
%     TTL_WAV_vs_TTLBox_run.m
% -------------------------------------------------------------------------

%% 1) Default inputs
if nargin < 1
    wavFile = '';
end
if nargin < 2
    ttlboxCsv = '';
end
if nargin < 3
    outDir = '';
end

%% 2) Validate input files
if isempty(wavFile) || ~safe_isfile(wavFile)
    error('step2_ttl_sync_mapping:MissingFile', ...
        'TTL WAV file is missing or invalid.');
end

if isempty(ttlboxCsv) || ~safe_isfile(ttlboxCsv)
    error('step2_ttl_sync_mapping:MissingFile', ...
        'TTLBox CSV file is missing or invalid.');
end

% Normalize types (helps older MATLAB + consistent printing)
wavFile   = char(string(wavFile));
ttlboxCsv = char(string(ttlboxCsv));

%% 3) Decide output folder
if isempty(outDir)
    outDir = fileparts(wavFile);
end
outDir = char(string(outDir));

% Create output folder if needed
if ~safe_isfolder(outDir)
    mkdir(outDir);
end

%% 4) Run sync mapping
% Return the full struct from TTL_WAV_vs_TTLBox_run (keep app compatibility)
out = TTL_WAV_vs_TTLBox_run(wavFile, ttlboxCsv, outDir);

end
