function outXlsx = step5_export_event_locked(fpMat, ttlCsv, usvMat, outDir, syncXlsx)
% step5_export_event_locked
% -------------------------------------------------------------------------
% PURPOSE
%   Export one per-second "event-locked" Excel for one experiment.
%
% OUTPUT LAYOUT
%   One row per second:
%       Time_s | 4 TTL event columns | Peaks | USV subtype columns
%
% INPUT POLICY
%   - TTLBox CSV        : optional but preferred
%   - Corrected FP MAT  : optional (used for Peaks)
%   - USV MAT           : optional (shifted preferred)
%   - Sync XLSX         : optional, used only if USV MAT is NOT already shifted
%
% IMPORTANT
%   At least one of TTL / FP / USV must exist.
% -------------------------------------------------------------------------

%% 1) Defaults
if nargin < 1, fpMat = ''; end
if nargin < 2, ttlCsv = ''; end
if nargin < 3, usvMat = ''; end
if nargin < 4, outDir = ''; end
if nargin < 5, syncXlsx = ''; end

%% 2) Normalize strings/chars
fpMat    = localToChar(fpMat);
ttlCsv   = localToChar(ttlCsv);
usvMat   = localToChar(usvMat);
outDir   = localToChar(outDir);
syncXlsx = localToChar(syncXlsx);

%% 3) Validate that we have something to export
hasFP  = localIsFileSafe(fpMat);
hasTTL = localIsFileSafe(ttlCsv);
hasUSV = localIsFileSafe(usvMat);

if ~hasFP && ~hasTTL && ~hasUSV
    error('step5_export_event_locked:MissingInputs', ...
        'Need at least one valid input: TTLBox CSV, Corrected FP MAT, or USV MAT.');
end

%% 4) Output folder fallback
if ~localIsFolderSafe(outDir)
    if hasUSV
        outDir = fileparts(usvMat);
    elseif hasTTL
        outDir = fileparts(ttlCsv);
    elseif hasFP
        outDir = fileparts(fpMat);
    else
        outDir = pwd;
    end
end

if ~localIsFolderSafe(outDir)
    mkdir(outDir);
end

%% 5) Output filename
baseName = '';
if hasUSV
    [~, baseName] = fileparts(usvMat);
    baseName = localRemoveShiftedSuffix(baseName);
elseif hasTTL
    [~, baseName] = fileparts(ttlCsv);
elseif hasFP
    [~, baseName] = fileparts(fpMat);
end

if isempty(baseName)
    baseName = 'experiment';
end

baseName = localRemoveSpaces(baseName);
outXlsx = fullfile(outDir, [baseName '_event_locked.xlsx']);

%% 6) Sync rule
% If the chosen USV file is already shifted, do not pass syncXlsx.
useSync = false;
if hasUSV
    if contains(lower(string(usvMat)), "_shifted")
        useSync = false;
    elseif localIsFileSafe(syncXlsx)
        useSync = true;
    end
end

if ~useSync
    syncXlsx = '';
end

%% 7) Call the real builder
FP_TTL_USV_EventLocked_overview( ...
    'FPmat', fpMat, ...
    'TTLcsv', ttlCsv, ...
    'USVmat', usvMat, ...
    'OutXlsx', outXlsx, ...
    'SyncMappingXlsx', syncXlsx);

end

%% ======================== local helpers ========================

function s = localToChar(x)
if isempty(x)
    s = '';
    return;
end
try
    if isstring(x)
        if strlength(x) == 0
            s = '';
        else
            s = char(x);
        end
        return;
    end
catch
end
try
    if iscell(x)
        if isempty(x)
            s = '';
        else
            s = localToChar(x{1});
        end
        return;
    end
catch
end
try
    s = char(x);
catch
    s = '';
end
end

function tf = localIsFileSafe(p)
tf = false;
try
    if isempty(p), return; end
    tf = isfile(p);
catch
    tf = false;
end
end

function tf = localIsFolderSafe(p)
tf = false;
try
    if isempty(p), return; end
    tf = isfolder(p);
catch
    tf = false;
end
end

function nameOut = localRemoveShiftedSuffix(nameIn)
nameOut = char(string(nameIn));
if isempty(nameOut)
    return;
end

low = lower(nameOut);
if endsWith(low, '_shifted')
    nameOut = nameOut(1:end-8);
end
end

function sOut = localRemoveSpaces(sIn)
sOut = char(string(sIn));
if isempty(sOut)
    return;
end

keep = true(size(sOut));
for i = 1:numel(sOut)
    if sOut(i) == ' ' || sOut(i) == sprintf('\t')
        keep(i) = false;
    end
end
sOut = sOut(keep);
end
