function outMat = step1_fp_correction(photoCsv, outDir)
% step1_fp_correction  (DECLUSTERED / student-style)
% -------------------------------------------------------------------------
% PURPOSE
%   Small wrapper used by the Master App.
%   Converts a raw photometry CSV into a corrected photometry MAT file.
%
% INPUTS
%   photoCsv : path to photometry CSV
%   outDir   : output folder (optional)
%
% OUTPUT
%   outMat   : full path to the saved *_CorrectedSignal.mat file
%
% NOTE
%   The heavy work is done in:
%     FP_signalCorrection_run.m
% -------------------------------------------------------------------------

%% 1) Default inputs (beginner style)
if nargin < 1
    photoCsv = '';
end
if nargin < 2
    outDir = '';
end

%% 2) Validate photometry CSV
if isempty(photoCsv) || ~safe_isfile(photoCsv)
    error('step1_fp_correction:MissingFile', ...
        'Photometry CSV is missing or invalid.');
end

% Normalize type to char (safe for older MATLAB)
photoCsv = char(string(photoCsv));

%% 3) Decide output folder
if isempty(outDir)
    outDir = fileparts(photoCsv);
end
outDir = char(string(outDir));

% Create output folder if needed
if ~isfolder(outDir)
    mkdir(outDir);
end

%% 4) Run correction (no plots)
% Keep the app quiet: ShowPlots = false
outMat = FP_signalCorrection_run(photoCsv, ...
    'OutDir', outDir, ...
    'ShowPlots', false);

end
