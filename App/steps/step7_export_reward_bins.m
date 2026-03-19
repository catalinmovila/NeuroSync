function outXlsx = step7_export_reward_bins(fpMat, ttlCsv, usvMat, outDir, syncXlsx)
% step7_export_reward_bins
% -------------------------------------------------------------------------
% PURPOSE
%   Export reward-centered long-format bin tables to one Excel workbook with
%   3 sheets: pm2s, pm5s, pm10s
%   Each row = one reward event x one 1-second bin.
%
% INPUTS
%   fpMat    : corrected FP MAT (optional)
%   ttlCsv   : TTLBox CSV (required)
%   usvMat   : shifted USV MAT preferred, raw allowed (optional)
%   outDir   : output folder (optional)
%   syncXlsx : mapping XLSX used only when USV MAT is raw (optional)
%
% OUTPUT
%   outXlsx  : workbook path
% -------------------------------------------------------------------------

if nargin < 1, fpMat = ''; end
if nargin < 2, ttlCsv = ''; end
if nargin < 3, usvMat = ''; end
if nargin < 4, outDir = ''; end
if nargin < 5, syncXlsx = ''; end

if ~localIsFile(ttlCsv)
    error('step7_export_reward_bins:MissingTTL', 'TTLBox CSV is required for reward-centered exports.');
end

outXlsx = FP_TTL_USV_reward_export_build('bins', fpMat, ttlCsv, usvMat, outDir, syncXlsx);

end

function tf = localIsFile(p)
tf = false;
try
    if isempty(p), return; end
    if isstring(p), p = char(p); end
    tf = ischar(p) && isfile(p);
catch
    tf = false;
end
end
