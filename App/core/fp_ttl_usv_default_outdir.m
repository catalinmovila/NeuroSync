function [outDir, anchorPath] = fp_ttl_usv_default_outdir(outDir, anchorPath, selectedPath, otherOutDir)
% fp_ttl_usv_default_outdir  (DECLUSTERED / student-style)
% -------------------------------------------------------------------------
% PURPOSE
%   Implements the simple "Output files" folder rule for your Master App.
%
% RULE
%   1) The FIRST important input the user selects becomes the "anchor"
%      (photometry / TTLBox / WAV / USV). That first selection is stored in
%      anchorPath.
%
%   2) If outDir is empty, create:
%         <anchor folder>\Output files
%
%   3) Collision avoidance:
%      If MAIN and SECONDARY would both use the same output folder, the
%      second one becomes:
%         "Output files 2", "Output files 3", ...
%
% INPUTS
%   outDir       : current output folder (can be empty)
%   anchorPath   : stored first-selected path (file or folder; can be empty)
%   selectedPath : the new path the user just picked (file or folder; can be empty)
%   otherOutDir  : output folder used by the other experiment (for collisions)
%
% OUTPUTS
%   outDir, anchorPath : updated values (and outDir is created on disk)
% -------------------------------------------------------------------------

%% 1) Defaults
if nargin < 1
    outDir = '';
end
if nargin < 2
    anchorPath = '';
end
if nargin < 3
    selectedPath = '';
end
if nargin < 4
    otherOutDir = '';
end

%% 2) Convert to char safely (beginner style)
outDir       = localToChar(outDir);
anchorPath   = localToChar(anchorPath);
selectedPath = localToChar(selectedPath);
otherOutDir  = localToChar(otherOutDir);

%% 3) Set anchorPath on first meaningful selection
if isempty(anchorPath) && ~isempty(selectedPath)
    anchorPath = selectedPath;
end

%% 4) If outDir is already set, just make sure it exists and stop
if ~isempty(outDir)
    if ~safe_isfolder(outDir)
        mkdir(outDir);
    end
    return;
end

%% 5) Decide the base folder from anchorPath
baseFolder = '';

if ~isempty(anchorPath)
    if safe_isfolder(anchorPath)
        % anchor is already a folder
        baseFolder = anchorPath;

    elseif safe_isfile(anchorPath)
        % anchor is a file -> use its folder
        baseFolder = fileparts(anchorPath);

    else
        % anchor might be a non-existing path; still try fileparts
        baseFolder = fileparts(anchorPath);
    end
end

if isempty(baseFolder)
    baseFolder = pwd;
end

%% 6) Build default candidate "Output files"
baseName = 'Output files';
candidate = fullfile(baseFolder, baseName);

%% 7) Collision avoidance vs other experiment
% If the other experiment already uses the SAME candidate path, we append
% " 2", " 3", ... until we find a folder name that does not exist.
if ~isempty(otherOutDir) && strcmpi(otherOutDir, candidate)
    k = 2;

    while true
        altName = sprintf('%s %d', baseName, k);
        altPath = fullfile(baseFolder, altName);

        if ~safe_isfolder(altPath)
            candidate = altPath;
            break;
        end

        k = k + 1;
    end
end

%% 8) Save and create on disk
outDir = candidate;

if ~safe_isfolder(outDir)
    mkdir(outDir);
end

end

%% ========================= Local helper =========================
function c = localToChar(x)
% Convert string/cell/char/numeric(0) to char safely.
% Returns '' if it cannot be converted.

c = '';

try
    if isempty(x)
        return;
    end

    % uigetfile/uigetdir cancel often returns 0
    if isnumeric(x)
        if isequal(x,0)
            return;
        end
        % numeric path is not valid
        return;
    end

    if iscell(x)
        if isempty(x)
            return;
        end
        x = x{1};
    end

    if isstring(x)
        if ~isscalar(x)
            return;
        end
        if strlength(x) == 0
            return;
        end
        c = char(x);
        return;
    end

    if ischar(x)
        c = x;
        return;
    end

catch
    c = '';
end
end
