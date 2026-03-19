function outXlsx = step6_export_reward_metrics(fpMat, ttlCsv, usvMat, outDir, syncXlsx)
% step6_export_reward_metrics
% -------------------------------------------------------------------------
% PURPOSE
%   Export reward-centered metrics to one Excel workbook with 3 sheets:
%       pm2s, pm5s, pm10s
%   Each row = one Food or Drug reward event.
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
    error('step6_export_reward_metrics:MissingTTL', 'TTLBox CSV is required for reward-centered exports.');
end

outXlsx = FP_TTL_USV_reward_export_build('metrics', fpMat, ttlCsv, usvMat, outDir, syncXlsx);

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
