function outXlsx = step4_export_overview(fpMat, ttlCsv, usvMat, outDir, syncXlsx, ttlWav)
% step4_export_overview  (DECLUSTERED / student-style)
% -------------------------------------------------------------------------
% PURPOSE
%   Create the experiment overview Excel:
%     Corrected FP MAT + TTLBox CSV + (SHIFTED) USV MAT  ->  Excel overview
%
% IMPORTANT RULES (your rules)
%   1) For the overview Excel, use the SYNCED/SHIFTED USV MAT (correct timing).
%   2) For the output file name, use the RAW USV recording name:
%        <RAW_USV_NAME>_experiment_overview.xlsx
%      (we get RAW name by removing "_SHIFTED" from the USV filename).
%   3) If the USV MAT is already shifted, do NOT pass syncXlsx (avoid double shift).
%   4) The overview Excel also includes a "Rate per 5 minutes" column based on recording duration.
%
% INPUTS
%   fpMat    : corrected FP MAT file
%   ttlCsv   : TTLBox CSV file
%   usvMat   : USV MAT (prefer shifted/synced)
%   outDir   : output folder (optional)
%   syncXlsx : SYNC_MAPPING.xlsx (optional; used only if USV is NOT shifted)
%   ttlWav   : TTL WAV (optional; used for Rate per 5 minutes column)
%
% OUTPUT
%   outXlsx  : full path to the created Excel
% -------------------------------------------------------------------------

%% 1) Defaults
if nargin < 1, fpMat = ''; end
if nargin < 2, ttlCsv = ''; end
if nargin < 3, usvMat = ''; end
if nargin < 4, outDir = ''; end
if nargin < 5, syncXlsx = ''; end
if nargin < 6, ttlWav = ''; end

%% 2) Validate required inputs
if ~isFileSafe(fpMat)
    error('step4_export_overview:MissingFile', 'Corrected FP MAT is missing/invalid.');
end

if ~isFileSafe(ttlCsv)
    error('step4_export_overview:MissingFile', 'TTLBox CSV is missing/invalid.');
end

if ~isFileSafe(usvMat)
    error('step4_export_overview:MissingFile', 'USV MAT is missing/invalid.');
end

% Normalize to char (helps older MATLAB versions)
fpMat  = char(string(fpMat));
ttlCsv = char(string(ttlCsv));
usvMat = char(string(usvMat));

% TTL WAV is optional (used only to compute duration-based rates)
try
    ttlWav = char(string(ttlWav));
catch
    ttlWav = '';
end

%% 3) Output folder
% If outDir is missing/invalid: use folder of USV, else folder of FP, else pwd.
if ~isFolderSafe(outDir)
    try
        outDir = fileparts(usvMat);
    catch
        outDir = '';
    end
end

if ~isFolderSafe(outDir)
    try
        outDir = fileparts(fpMat);
    catch
        outDir = '';
    end
end

if ~isFolderSafe(outDir)
    outDir = pwd;
end

% Create folder if needed
if ~isFolderSafe(outDir)
    mkdir(outDir);
end

outDir = char(string(outDir));

%% 4) Output filename rule: RAW USV name + "_experiment_overview.xlsx"
[~, baseName] = fileparts(usvMat);
baseName = removeShiftedSuffix(baseName);
baseName = removeSpaces(baseName);

if isempty(baseName)
    baseName = 'USV';
end

outXlsx = fullfile(outDir, [baseName '_experiment_overview.xlsx']);

%% 5) Sync mapping rule
% If USV MAT already contains "_shifted", do not pass syncXlsx
useSync = true;

if contains(lower(string(usvMat)), "_shifted")
    useSync = false;
end

if ~isFileSafe(syncXlsx)
    useSync = false;
end

if ~useSync
    syncXlsx = '';
else
    syncXlsx = char(string(syncXlsx));
end

%% 6) Call the real overview builder
% (This function does the work and writes the Excel file.)
FP_TTL_USV_Experiment_overview( ...
    'FPmat', fpMat, ...
    'TTLcsv', ttlCsv, ...
    'USVmat', usvMat, ...
    'OutXlsx', outXlsx, ...
    'SyncMappingXlsx', syncXlsx, ...
    'TTLWav', ttlWav);

end

%% ========================= helper functions =========================

function nameOut = removeShiftedSuffix(nameIn)
% Remove "_SHIFTED" at the end (case-insensitive).

nameOut = nameIn;

% Try a few common variants (very beginner-style)
if endsWith(nameOut, '_SHIFTED')
    nameOut = nameOut(1:end-8);
    return;
end

if endsWith(nameOut, '_shifted')
    nameOut = nameOut(1:end-8);
    return;
end

% If mixed case exists, do a case-insensitive check by comparing lower()
low = lower(nameOut);
if endsWith(low, '_shifted')
    nameOut = nameOut(1:end-8);
end

end

function sOut = removeSpaces(sIn)
% Remove spaces and tabs from a filename (safe).
sOut = sIn;

if isempty(sOut)
    return;
end

% Convert to char for indexing
sOut = char(string(sOut));

keep = true(size(sOut));
for i = 1:numel(sOut)
    if sOut(i) == ' ' || sOut(i) == sprintf('\t')
        keep(i) = false;
    end
end

sOut = sOut(keep);

end

function tf = isFileSafe(p)
% Safe isfile check; accepts string/char/cell and uigetfile 0.

tf = false;

try
    if isempty(p), return; end
    if isnumeric(p) && isequal(p,0), return; end

    if iscell(p)
        if isempty(p), return; end
        p = p{1};
    end

    if isstring(p)
        if ~isscalar(p), return; end
        if strlength(p) == 0, return; end
        p = char(p);
    end

    if ischar(p)
        if isempty(p), return; end
        tf = isfile(p);
    end
catch
    tf = false;
end
end

function tf = isFolderSafe(p)
% Safe isfolder check; accepts string/char/cell and uigetdir 0.

tf = false;

try
    if isempty(p), return; end
    if isnumeric(p) && isequal(p,0), return; end

    if iscell(p)
        if isempty(p), return; end
        p = p{1};
    end

    if isstring(p)
        if ~isscalar(p), return; end
        if strlength(p) == 0, return; end
        p = char(p);
    end

    if ischar(p)
        if isempty(p), return; end
        tf = isfolder(p);
    end
catch
    tf = false;
end
end
