function [outMat, a, b] = step3_apply_usv_shift(syncXlsx, usvMat, outDir)
% step3_apply_usv_shift  (DECLUSTERED / student-style)
% -------------------------------------------------------------------------
% PURPOSE
%   Wrapper used by the Master App.
%   Uses the audio->TTLBox sync mapping (SYNC_MAPPING.xlsx) to shift the
%   timestamps in a DeepSqueak detection MAT file.
%
% INPUTS
%   syncXlsx : path to *_SYNC_MAPPING.xlsx
%   usvMat   : path to DeepSqueak detection .mat
%   outDir   : folder for the shifted MAT (optional)
%
% OUTPUTS
%   outMat : path to the shifted .mat
%   a, b   : mapping coefficients for:  t_TTLBox = a * t_audio + b
%
% NOTE
%   Heavy work is done in:
%     USV_Timeline_shift_run.m
% -------------------------------------------------------------------------

%% 1) Defaults (beginner style)
if nargin < 1
    syncXlsx = '';
end
if nargin < 2
    usvMat = '';
end
if nargin < 3
    outDir = '';
end

%% 2) Validate input files
if isempty(syncXlsx) || ~safe_isfile(syncXlsx)
    error('step3_apply_usv_shift:MissingFile', ...
        'Sync mapping XLSX is missing or invalid.');
end

if isempty(usvMat) || ~safe_isfile(usvMat)
    error('step3_apply_usv_shift:MissingFile', ...
        'USV (DeepSqueak) MAT is missing or invalid.');
end

% Normalize to char for safety (older MATLAB)
syncXlsx = char(string(syncXlsx));
usvMat   = char(string(usvMat));

%% 3) Decide output folder
if isempty(outDir)
    % Default: next to the USV detection file
    outDir = fileparts(usvMat);
end
outDir = char(string(outDir));

% Create folder if needed
if ~safe_isfolder(outDir)
    mkdir(outDir);
end

%% 4) Build output file name
[~, baseName] = fileparts(usvMat);
outCandidate = fullfile(outDir, [baseName '_SHIFTED.mat']);

%% 5) Run the shift (do NOT overwrite by default)
[outMat, a, b] = USV_Timeline_shift_run(syncXlsx, usvMat, ...
    'OutMat', outCandidate, ...
    'Overwrite', false);

end
