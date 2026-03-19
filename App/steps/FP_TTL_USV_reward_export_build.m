function outXlsx = FP_TTL_USV_reward_export_build(mode, fpMat, ttlCsv, usvMat, outDir, syncXlsx)
% FP_TTL_USV_reward_export_build
% -------------------------------------------------------------------------
% Shared builder for reward-centered exports.
%
% mode = 'metrics'
%   -> workbook with sheets pm2s / pm5s / pm10s
%   -> each row = one Food/Drug reward event
%
% mode = 'bins'
%   -> workbook with sheets pm2s / pm5s / pm10s
%   -> each row = one reward event x one 1-second bin
% -------------------------------------------------------------------------

if nargin < 1, mode = 'metrics'; end
if nargin < 2, fpMat = ''; end
if nargin < 3, ttlCsv = ''; end
if nargin < 4, usvMat = ''; end
if nargin < 5, outDir = ''; end
if nargin < 6, syncXlsx = ''; end

mode = lower(char(string(mode)));
fpMat = localToChar(fpMat);
ttlCsv = localToChar(ttlCsv);
usvMat = localToChar(usvMat);
outDir = localToChar(outDir);
syncXlsx = localToChar(syncXlsx);

if ~strcmp(mode,'metrics') && ~strcmp(mode,'bins')
    error('FP_TTL_USV_reward_export_build:BadMode', 'Mode must be ''metrics'' or ''bins''.');
end

if ~localIsFile(ttlCsv)
    error('FP_TTL_USV_reward_export_build:MissingTTL', 'TTLBox CSV is required.');
end

hasFP = localIsFile(fpMat);
hasUSV = localIsFile(usvMat);
hasSync = localIsFile(syncXlsx);

% Output folder
if ~localIsFolder(outDir)
    if hasUSV
        outDir = fileparts(usvMat);
    elseif hasFP
        outDir = fileparts(fpMat);
    else
        outDir = fileparts(ttlCsv);
    end
end
if ~localIsFolder(outDir)
    outDir = pwd;
end
if ~localIsFolder(outDir)
    mkdir(outDir);
end

sessionStem = localBuildSessionStem(usvMat, ttlCsv, fpMat);
if isempty(sessionStem)
    sessionStem = 'session';
end
if strcmp(mode,'metrics')
    outXlsx = fullfile(outDir, [sessionStem '_reward_event_metrics.xlsx']);
else
    outXlsx = fullfile(outDir, [sessionStem '_reward_bin_table.xlsx']);
end
if exist(outXlsx, 'file') == 2
    delete(outXlsx);
end

% Load TTL and reward times
TTL = localParseTTLBox(ttlCsv);
leftTimes = TTL.times_s(TTL.code_ms == 20);
rightTimes = TTL.times_s(TTL.code_ms == 40);
drugTimes = TTL.times_s(TTL.code_ms == 60);
foodTimes = TTL.times_s(TTL.code_ms == 80);
if isempty(foodTimes) && isempty(drugTimes)
    error('FP_TTL_USV_reward_export_build:NoRewards', 'No Food or Drug reward pulses were found in the TTLBox CSV.');
end

% Load FP and peaks (optional)
fpTime_s = zeros(0,1);
fpSignal = zeros(0,1);
peakTimes = zeros(0,1);
if hasFP
    [fpTime_s, fpSignal] = localLoadCorrectedFP(fpMat);
    if ~isempty(fpTime_s)
        fpTime_s = fpTime_s - fpTime_s(1);
    end
    [~, peakTimes] = localFindPeaks(fpTime_s, fpSignal);
    peakTimes = peakTimes(:);
end

% Load USV (optional, shifted preferred / raw allowed)
usvTimes_s = zeros(0,1);
usvLabels = cell(0,1);
if hasUSV
    [usvTimes_s, usvLabels] = localLoadUSVCalls(usvMat);
    usvTimes_s = usvTimes_s(:);
    if ~contains(lower(usvMat), '_shifted') && hasSync
        [mapA, mapB] = localReadSyncMapping(syncXlsx);
        usvTimes_s = mapA .* usvTimes_s + mapB;
    end
end

% Metadata bundle used in every sheet
meta = struct();
meta.sessionStem = sessionStem;
meta.ttlBase = localBaseName(ttlCsv);
meta.fpBase = localBaseName(fpMat);
meta.usvBase = localBaseName(usvMat);
meta.ratGuess = localGuessRat(sessionStem, meta.ttlBase, meta.usvBase, meta.fpBase);
meta.dateGuess = localGuessDate(sessionStem, meta.ttlBase, meta.usvBase, meta.fpBase);
meta.hasFP = hasFP;
meta.hasUSV = hasUSV;

% Stable USV column list for cross-session stacking
usvHeaders = { ...
    'Complex'
    'Upward Ramp'
    'Downward Ramp'
    'Flat'
    'Short'
    'Split'
    'Step Up'
    'Step Down'
    'Multi-Step'
    'Trill'
    'Flat-trill'
    'Trill with Jumps'
    'Inverted U'
    'Composite'
    '22-KHz'
    'Unclear'
    'Miscellaneuous'};

writecell(localBuildReadMeSheet(mode, meta, ttlCsv, fpMat, usvMat, syncXlsx), outXlsx, 'Sheet', 'Read_Me');

guideWritten = false;
wins = [2 5 10];
for iW = 1:numel(wins)
    win_s = wins(iW);
    if strcmp(mode,'metrics')
        C = localBuildMetricsSheet(win_s, meta, foodTimes, drugTimes, leftTimes, rightTimes, ...
            fpTime_s, fpSignal, peakTimes, usvTimes_s, usvLabels, usvHeaders);
    else
        C = localBuildBinsSheet(win_s, meta, foodTimes, drugTimes, leftTimes, rightTimes, ...
            fpTime_s, fpSignal, peakTimes, usvTimes_s, usvLabels, usvHeaders);
    end

    if ~guideWritten
        writecell(localBuildGuideSheet(mode, C(1,:)), outXlsx, 'Sheet', 'Column_Guide');
        guideWritten = true;
    end

    C = localHumanizeDataSheet(C, mode, win_s);
    writecell(C, outXlsx, 'Sheet', localWindowSheetName(mode, win_s));
end

end

%% =====================================================================
% SHEET BUILDERS
% ======================================================================

function C = localBuildMetricsSheet(win_s, meta, foodTimes, drugTimes, leftTimes, rightTimes, fpTime_s, fpSignal, peakTimes, usvTimes_s, usvLabels, usvHeaders)

[eventTimes, rewardTypes, rewardIdxWithinType] = localCombineRewards(foodTimes, drugTimes);
nEvents = numel(eventTimes);

fixedNorm = cell(numel(usvHeaders),1);
for i = 1:numel(usvHeaders)
    fixedNorm{i} = localNormLabel(usvHeaders{i});
end
unclearIdx = find(strcmp(fixedNorm, 'unclear'), 1);
if isempty(unclearIdx)
    unclearIdx = numel(fixedNorm);
end

hdr = { ...
    'RowID','SessionStem','RatID_guess','Date_guess','RewardType','RewardIndexWithinType','RewardTime_s','Window_s', ...
    'FP_available','USV_available', ...
    'FP_Baseline_Pre','FP_Mean_Pre','FP_Mean_Post','FP_AUC_Pre','FP_AUC_Post','FP_Max_Post','FP_Min_Pre','FP_Peak_Latency_Post_s', ...
    'Peak_Count_Pre','Peak_Count_Post','FirstPeak_Latency_Post_s', ...
    'LeftLever_Pre','LeftLever_Post','RightLever_Pre','RightLever_Post', ...
    'FoodReward_Pre','FoodReward_Post','DrugReward_Pre','DrugReward_Post', ...
    'TotalUSV_Pre','TotalUSV_Post','FirstUSV_Latency_Post_s'};

% add stable USV subtype columns
for i = 1:numel(usvHeaders)
    hdr{end+1} = [usvHeaders{i} '_Pre']; %#ok<AGROW>
    hdr{end+1} = [usvHeaders{i} '_Post']; %#ok<AGROW>
end

C = cell(nEvents + 1, numel(hdr));
C(1,:) = hdr;

for i = 1:nEvents
    t0 = eventTimes(i);
    aPre = t0 - win_s;
    bPre = t0;
    aPost = t0;
    bPost = t0 + win_s;

    row = cell(1, numel(hdr));
    c = 1;
    row{c} = i; c=c+1;
    row{c} = meta.sessionStem; c=c+1;
    row{c} = meta.ratGuess; c=c+1;
    row{c} = meta.dateGuess; c=c+1;
    row{c} = rewardTypes{i}; c=c+1;
    row{c} = rewardIdxWithinType(i); c=c+1;
    row{c} = t0; c=c+1;
    row{c} = win_s; c=c+1;
    row{c} = double(meta.hasFP); c=c+1;
    row{c} = double(meta.hasUSV); c=c+1;

    % FP + peaks
    if meta.hasFP && ~isempty(fpTime_s)
        [xPre, yPreRaw] = localIntervalTrace(fpTime_s, fpSignal, aPre, bPre, false);
        [xPost, yPostRaw] = localIntervalTrace(fpTime_s, fpSignal, aPost, bPost, false);
        base = localMeanOrNaN(yPreRaw);
        if ~isfinite(base)
            base = 0;
        end
        yPre = yPreRaw - base;
        yPost = yPostRaw - base;

        row{c} = base; c=c+1;
        row{c} = localMeanOrNaN(yPre); c=c+1;
        row{c} = localMeanOrNaN(yPost); c=c+1;
        row{c} = localAUCOrNaN(xPre, yPre); c=c+1;
        row{c} = localAUCOrNaN(xPost, yPost); c=c+1;
        row{c} = localMaxOrBlank(yPost); c=c+1;
        row{c} = localMinOrBlank(yPre); c=c+1;
        row{c} = localPeakLatencyFromTrace(xPost, yPost, t0); c=c+1;

        row{c} = sum(peakTimes >= aPre & peakTimes < bPre); c=c+1;
        row{c} = sum(peakTimes >= aPost & peakTimes < bPost); c=c+1;
        row{c} = localFirstLatency(peakTimes, aPost, bPost, t0); c=c+1;
    else
        for k = 1:11
            row{c} = ''; c=c+1;
        end
    end

    % TTL counts always available because TTL is required
    row{c} = sum(leftTimes  >= aPre  & leftTimes  < bPre);  c=c+1;
    row{c} = sum(leftTimes  >= aPost & leftTimes  < bPost); c=c+1;
    row{c} = sum(rightTimes >= aPre  & rightTimes < bPre);  c=c+1;
    row{c} = sum(rightTimes >= aPost & rightTimes < bPost); c=c+1;
    row{c} = sum(foodTimes  >= aPre  & foodTimes  < bPre);  c=c+1;
    row{c} = sum(foodTimes  >= aPost & foodTimes  < bPost); c=c+1;
    row{c} = sum(drugTimes  >= aPre  & drugTimes  < bPre);  c=c+1;
    row{c} = sum(drugTimes  >= aPost & drugTimes  < bPost); c=c+1;

    % USV counts
    if meta.hasUSV && ~isempty(usvTimes_s)
        usvPre = zeros(1, numel(usvHeaders));
        usvPost = zeros(1, numel(usvHeaders));
        firstPostLat = NaN;
        totalPre = 0;
        totalPost = 0;

        for j = 1:numel(usvTimes_s)
            tu = usvTimes_s(j);
            if ~isfinite(tu)
                continue;
            end
            key = localNormLabel(usvLabels{j});
            idxLabel = find(strcmp(fixedNorm, key), 1);
            if isempty(idxLabel)
                idxLabel = unclearIdx;
            end
            if tu >= aPre && tu < bPre
                usvPre(idxLabel) = usvPre(idxLabel) + 1;
                totalPre = totalPre + 1;
            elseif tu >= aPost && tu < bPost
                usvPost(idxLabel) = usvPost(idxLabel) + 1;
                totalPost = totalPost + 1;
                if ~isfinite(firstPostLat)
                    firstPostLat = tu - t0;
                end
            end
        end

        row{c} = totalPre; c=c+1;
        row{c} = totalPost; c=c+1;
        row{c} = firstPostLat; c=c+1;
        for j = 1:numel(usvHeaders)
            row{c} = usvPre(j); c=c+1;
            row{c} = usvPost(j); c=c+1;
        end
    else
        row{c} = ''; c=c+1;
        row{c} = ''; c=c+1;
        row{c} = ''; c=c+1;
        for j = 1:(2*numel(usvHeaders))
            row{c} = ''; c=c+1;
        end
    end

    C(i+1,:) = row;
end

end

function C = localBuildBinsSheet(win_s, meta, foodTimes, drugTimes, leftTimes, rightTimes, fpTime_s, fpSignal, peakTimes, usvTimes_s, usvLabels, usvHeaders)

[eventTimes, rewardTypes, rewardIdxWithinType] = localCombineRewards(foodTimes, drugTimes);
fixedNorm = cell(numel(usvHeaders),1);
for i = 1:numel(usvHeaders)
    fixedNorm{i} = localNormLabel(usvHeaders{i});
end
unclearIdx = find(strcmp(fixedNorm, 'unclear'), 1);
if isempty(unclearIdx)
    unclearIdx = numel(fixedNorm);
end

edges = -win_s:1:win_s;
if edges(end) < win_s
    edges(end+1) = win_s;
end
nBins = numel(edges) - 1;
nRows = numel(eventTimes) * nBins;

hdr = { ...
    'RowID','SessionStem','RatID_guess','Date_guess','RewardType','RewardIndexWithinType','RewardTime_s','Window_s', ...
    'BinIndex','BinStart_Rel_s','BinEnd_Rel_s','BinCenter_Rel_s','FP_available','USV_available', ...
    'FP_BinMean','PeakCount','LeftLeverCount','RightLeverCount','FoodRewardCount','DrugRewardCount','TotalUSVCount'};
for i = 1:numel(usvHeaders)
    hdr{end+1} = [usvHeaders{i} '_Count']; %#ok<AGROW>
end

C = cell(nRows + 1, numel(hdr));
C(1,:) = hdr;

rowID = 0;
for i = 1:numel(eventTimes)
    t0 = eventTimes(i);
    aPre = t0 - win_s;
    bPre = t0;
    base = 0;
    if meta.hasFP && ~isempty(fpTime_s)
        [~, yPreRaw] = localIntervalTrace(fpTime_s, fpSignal, aPre, bPre, false);
        base = localMeanOrNaN(yPreRaw);
        if ~isfinite(base)
            base = 0;
        end
    end

    for b = 1:nBins
        rowID = rowID + 1;
        relA = edges(b);
        relB = edges(b+1);
        absA = t0 + relA;
        absB = t0 + relB;

        row = cell(1, numel(hdr));
        c = 1;
        row{c} = rowID; c=c+1;
        row{c} = meta.sessionStem; c=c+1;
        row{c} = meta.ratGuess; c=c+1;
        row{c} = meta.dateGuess; c=c+1;
        row{c} = rewardTypes{i}; c=c+1;
        row{c} = rewardIdxWithinType(i); c=c+1;
        row{c} = t0; c=c+1;
        row{c} = win_s; c=c+1;
        row{c} = b; c=c+1;
        row{c} = relA; c=c+1;
        row{c} = relB; c=c+1;
        row{c} = (relA + relB) / 2; c=c+1;
        row{c} = double(meta.hasFP); c=c+1;
        row{c} = double(meta.hasUSV); c=c+1;

        if meta.hasFP && ~isempty(fpTime_s)
            [~, yBinRaw] = localIntervalTrace(fpTime_s, fpSignal, absA, absB, b == nBins);
            row{c} = localMeanOrNaN(yBinRaw - base); c=c+1;
            row{c} = sum(peakTimes >= absA & peakTimes < absB); c=c+1;
        else
            row{c} = ''; c=c+1;
            row{c} = ''; c=c+1;
        end

        row{c} = sum(leftTimes  >= absA & leftTimes  < absB); c=c+1;
        row{c} = sum(rightTimes >= absA & rightTimes < absB); c=c+1;
        row{c} = sum(foodTimes  >= absA & foodTimes  < absB); c=c+1;
        row{c} = sum(drugTimes  >= absA & drugTimes  < absB); c=c+1;

        if meta.hasUSV && ~isempty(usvTimes_s)
            counts = zeros(1, numel(usvHeaders));
            totalUSV = 0;
            for j = 1:numel(usvTimes_s)
                tu = usvTimes_s(j);
                if ~(isfinite(tu) && tu >= absA && tu < absB)
                    continue;
                end
                key = localNormLabel(usvLabels{j});
                idxLabel = find(strcmp(fixedNorm, key), 1);
                if isempty(idxLabel)
                    idxLabel = unclearIdx;
                end
                counts(idxLabel) = counts(idxLabel) + 1;
                totalUSV = totalUSV + 1;
            end
            row{c} = totalUSV; c=c+1;
            for j = 1:numel(usvHeaders)
                row{c} = counts(j); c=c+1;
            end
        else
            row{c} = ''; c=c+1;
            for j = 1:numel(usvHeaders)
                row{c} = ''; c=c+1;
            end
        end

        C(rowID + 1,:) = row;
    end
end

end


function C2 = localHumanizeDataSheet(C, mode, win_s)
origHdr = C(1,:);
[newHdr, ~] = localFriendlyHeaderInfo(mode, origHdr);

if strcmp(mode, 'metrics')
    top1 = sprintf('Reward-event summary table for a ±%gs window', win_s);
    top2 = 'One row = one reward event (Food or Drug reward).';
    top3 = '"Before reward" means [reward-window, reward). "After reward" means [reward, reward+window). Empty cells usually mean that the needed file was not available.';
else
    top1 = sprintf('Reward-bin table for a ±%gs window', win_s);
    top2 = 'One row = one reward event x one 1-second time bin around that reward.';
    top3 = 'Use this sheet for heatmaps or time-course plots. Bin times are relative to the reward, where 0 s is the reward moment.';
end

C2 = cell(size(C,1) + 4, size(C,2));
C2(1,1) = {top1};
C2(2,1) = {top2};
C2(3,1) = {top3};
C2(5,:) = newHdr;
C2(6:end,:) = C(2:end,:);
end

function G = localBuildGuideSheet(mode, origHdr)
[newHdr, desc] = localFriendlyHeaderInfo(mode, origHdr);
G = cell(numel(newHdr) + 2, 3);
G(1,:) = {'Column name in workbook', 'What it means', 'Notes'};
for i = 1:numel(newHdr)
    G{i+1,1} = newHdr{i};
    G{i+1,2} = desc{i};
    if strcmp(mode, 'metrics')
        G{i+1,3} = 'This value belongs to one reward event row.';
    else
        G{i+1,3} = 'This value belongs to one reward-bin row.';
    end
end
G(end,1) = {'Tip'};
G(end,2) = {'Look at the Read_Me sheet first. Then use the window sheets (2 s, 5 s, 10 s) for the actual data.'};
G(end,3) = {'Blank cells usually mean the photometry file or the USV file was not available.'};
end

function R = localBuildReadMeSheet(mode, meta, ttlCsv, fpMat, usvMat, syncXlsx)
if strcmp(mode, 'metrics')
    exportName = 'Reward-event metrics export';
    dataShape = 'One row = one reward event.';
else
    exportName = 'Reward-bin export';
    dataShape = 'One row = one reward event x one 1-second time bin.';
end

R = {
    'Read Me', '';
    'Export type', exportName;
    'How rows are organized', dataShape;
    'Session name', meta.sessionStem;
    'Rat ID guess', meta.ratGuess;
    'Date guess', meta.dateGuess;
    'TTL file used', localBaseName(ttlCsv);
    'Corrected photometry file used', localBaseName(fpMat);
    'USV file used', localBaseName(usvMat);
    'Sync mapping file used', localBaseName(syncXlsx);
    'Important note about time', 'Reward Time (s) is on this export''s aligned session time base. Compare times inside the same export family unless you explicitly account for any offset between export types.';
    'How to read windows', '2 s means ±2 s around reward, 5 s means ±5 s, and 10 s means ±10 s.';
    'How to read before/after', 'Before reward = from reward-window up to just before reward. After reward = from reward to reward+window.';
    'How missing data is shown', 'Blank cells usually mean that photometry or USV data were not available for that session.';
    'Where column meanings are explained', 'See the Column_Guide sheet.'};
end

function [newHdr, desc] = localFriendlyHeaderInfo(mode, origHdr)
newHdr = cell(size(origHdr));
desc = cell(size(origHdr));
for i = 1:numel(origHdr)
    old = char(string(origHdr{i}));
    [newHdr{i}, desc{i}] = localExplainColumn(old, mode);
end
end

function [niceName, meaning] = localExplainColumn(old, mode)
old = char(string(old));

switch old
    case 'RowID'
        niceName = 'Export Row Number';
        meaning = 'Simple row counter inside this sheet.';
    case 'SessionStem'
        niceName = 'Session Name';
        meaning = 'Short session label built from the file names.';
    case 'RatID_guess'
        niceName = 'Rat ID (guessed from file name)';
        meaning = 'Rat identifier guessed from the file names.';
    case 'Date_guess'
        niceName = 'Date (guessed from file name)';
        meaning = 'Session date guessed from the file names.';
    case 'RewardType'
        niceName = 'Reward Type';
        meaning = 'Food reward or Drug reward.';
    case 'RewardIndexWithinType'
        niceName = 'Reward Number Within Type';
        meaning = 'For example, Food reward #1, #2, #3 or Drug reward #1, #2, etc.';
    case 'RewardTime_s'
        niceName = 'Reward Time (s)';
        meaning = 'Reward timestamp in seconds on this export''s aligned session time base.';
    case 'Window_s'
        niceName = 'Analysis Window Size (s)';
        meaning = 'How far before and after the reward the analysis looked.';
    case 'FP_available'
        niceName = 'Photometry File Available (1=yes, 0=no)';
        meaning = 'Shows whether a corrected photometry file was available for this export.';
    case 'USV_available'
        niceName = 'USV File Available (1=yes, 0=no)';
        meaning = 'Shows whether a USV file was available for this export.';
    case 'FP_Baseline_Pre'
        niceName = 'Photometry Baseline Before Reward';
        meaning = 'Average photometry signal in the pre-reward window before baseline correction.';
    case 'FP_Mean_Pre'
        niceName = 'Mean Photometry Before Reward';
        meaning = 'Average baseline-corrected photometry signal before the reward.';
    case 'FP_Mean_Post'
        niceName = 'Mean Photometry After Reward';
        meaning = 'Average baseline-corrected photometry signal after the reward.';
    case 'FP_AUC_Pre'
        niceName = 'Photometry Area Before Reward';
        meaning = 'Area under the baseline-corrected photometry trace before the reward.';
    case 'FP_AUC_Post'
        niceName = 'Photometry Area After Reward';
        meaning = 'Area under the baseline-corrected photometry trace after the reward.';
    case 'FP_Max_Post'
        niceName = 'Highest Photometry After Reward';
        meaning = 'Maximum baseline-corrected photometry value after the reward.';
    case 'FP_Min_Pre'
        niceName = 'Lowest Photometry Before Reward';
        meaning = 'Minimum baseline-corrected photometry value before the reward.';
    case 'FP_Peak_Latency_Post_s'
        niceName = 'Time To Highest Photometry After Reward (s)';
        meaning = 'Time from reward to the highest photometry value in the post-reward window.';
    case 'Peak_Count_Pre'
        niceName = 'Peak Count Before Reward';
        meaning = 'Number of detected photometry peaks before the reward.';
    case 'Peak_Count_Post'
        niceName = 'Peak Count After Reward';
        meaning = 'Number of detected photometry peaks after the reward.';
    case 'FirstPeak_Latency_Post_s'
        niceName = 'Time To First Peak After Reward (s)';
        meaning = 'Time from reward to the first detected photometry peak after the reward.';
    case 'LeftLever_Pre'
        niceName = 'Left Lever Presses Before Reward';
        meaning = 'Number of 20 ms left-lever TTL events before the reward.';
    case 'LeftLever_Post'
        niceName = 'Left Lever Presses After Reward';
        meaning = 'Number of 20 ms left-lever TTL events after the reward.';
    case 'RightLever_Pre'
        niceName = 'Right Lever Presses Before Reward';
        meaning = 'Number of 40 ms right-lever TTL events before the reward.';
    case 'RightLever_Post'
        niceName = 'Right Lever Presses After Reward';
        meaning = 'Number of 40 ms right-lever TTL events after the reward.';
    case 'FoodReward_Pre'
        niceName = 'Food Reward Pulses Before Reward';
        meaning = 'Number of food-reward TTL pulses before the reward.';
    case 'FoodReward_Post'
        niceName = 'Food Reward Pulses After Reward';
        meaning = 'Number of food-reward TTL pulses after the reward.';
    case 'DrugReward_Pre'
        niceName = 'Drug Reward Pulses Before Reward';
        meaning = 'Number of drug-reward TTL pulses before the reward.';
    case 'DrugReward_Post'
        niceName = 'Drug Reward Pulses After Reward';
        meaning = 'Number of drug-reward TTL pulses after the reward.';
    case 'TotalUSV_Pre'
        niceName = 'Total USV Calls Before Reward';
        meaning = 'Total number of accepted USV calls before the reward.';
    case 'TotalUSV_Post'
        niceName = 'Total USV Calls After Reward';
        meaning = 'Total number of accepted USV calls after the reward.';
    case 'FirstUSV_Latency_Post_s'
        niceName = 'Time To First USV After Reward (s)';
        meaning = 'Time from reward to the first accepted USV call after the reward.';
    case 'BinIndex'
        niceName = 'Bin Number Within Window';
        meaning = 'Running bin number inside the selected window around the reward.';
    case 'BinStart_Rel_s'
        niceName = 'Bin Start Relative To Reward (s)';
        meaning = 'Start time of this 1-second bin, relative to the reward.';
    case 'BinEnd_Rel_s'
        niceName = 'Bin End Relative To Reward (s)';
        meaning = 'End time of this 1-second bin, relative to the reward.';
    case 'BinCenter_Rel_s'
        niceName = 'Bin Center Relative To Reward (s)';
        meaning = 'Center time of this 1-second bin, relative to the reward.';
    case 'FP_BinMean'
        niceName = 'Mean Photometry In This Bin';
        meaning = 'Average baseline-corrected photometry signal inside this specific bin.';
    case 'PeakCount'
        niceName = 'Peak Count In This Bin';
        meaning = 'Number of detected photometry peaks inside this specific bin.';
    case 'LeftLeverCount'
        niceName = 'Left Lever Presses In This Bin';
        meaning = 'Number of left-lever TTL events inside this specific bin.';
    case 'RightLeverCount'
        niceName = 'Right Lever Presses In This Bin';
        meaning = 'Number of right-lever TTL events inside this specific bin.';
    case 'FoodRewardCount'
        niceName = 'Food Reward Pulses In This Bin';
        meaning = 'Number of food-reward TTL pulses inside this specific bin.';
    case 'DrugRewardCount'
        niceName = 'Drug Reward Pulses In This Bin';
        meaning = 'Number of drug-reward TTL pulses inside this specific bin.';
    case 'TotalUSVCount'
        niceName = 'Total USV Calls In This Bin';
        meaning = 'Total number of accepted USV calls inside this specific bin.';
    otherwise
        if endsWith(old, '_Pre')
            base = extractBefore(string(old), strlength(string(old)) - 3);
            base = char(base);
            niceName = [base ' Calls Before Reward'];
            meaning = ['Number of accepted USV calls labeled as ' base ' before the reward.'];
        elseif endsWith(old, '_Post')
            base = extractBefore(string(old), strlength(string(old)) - 4);
            base = char(base);
            niceName = [base ' Calls After Reward'];
            meaning = ['Number of accepted USV calls labeled as ' base ' after the reward.'];
        elseif endsWith(old, '_Count')
            base = extractBefore(string(old), strlength(string(old)) - 5);
            base = char(base);
            niceName = [base ' Calls In This Bin'];
            meaning = ['Number of accepted USV calls labeled as ' base ' inside this specific bin.'];
        else
            niceName = old;
            meaning = 'See the Read_Me sheet for general interpretation.';
        end
end

if strcmp(mode, 'bins') && contains(niceName, 'Before Reward')
    % no special change; keep if ever present
end
end

function name = localWindowSheetName(mode, win_s)
if strcmp(mode, 'metrics')
    name = sprintf('Events_%gs', win_s);
else
    name = sprintf('Bins_%gs', win_s);
end
name = strrep(name, '.', 'p');
end


%% =====================================================================
% SMALL HELPERS
% ======================================================================

function [times, types, idxWithin] = localCombineRewards(foodTimes, drugTimes)
times = [foodTimes(:); drugTimes(:)];
types = [repmat({'Food'}, numel(foodTimes), 1); repmat({'Drug'}, numel(drugTimes), 1)];
idxWithin = [(1:numel(foodTimes))'; (1:numel(drugTimes))'];
[~, ord] = sort(times);
times = times(ord);
types = types(ord);
idxWithin = idxWithin(ord);
end

function name = localSheetName(win_s)
name = sprintf('pm%gs', win_s);
name = strrep(name, '.', 'p');
end

function s = localToChar(x)
if isempty(x)
    s = '';
elseif isstring(x)
    if isscalar(x)
        s = char(x);
    else
        s = char(x(1));
    end
elseif ischar(x)
    s = x;
else
    s = char(string(x));
end
end

function tf = localIsFile(p)
tf = false;
try
    p = localToChar(p);
    tf = ~isempty(p) && isfile(p);
catch
    tf = false;
end
end

function tf = localIsFolder(p)
tf = false;
try
    p = localToChar(p);
    tf = ~isempty(p) && isfolder(p);
catch
    tf = false;
end
end

function stem = localBuildSessionStem(usvMat, ttlCsv, fpMat)
stem = '';
base = localBaseName(usvMat);
if isempty(base)
    base = localBaseName(ttlCsv);
end
if isempty(base)
    base = localBaseName(fpMat);
end
if isempty(base)
    stem = 'session';
    return;
end
base = regexprep(base, '_SHIFTED$', '', 'ignorecase');
base = regexprep(base, '_CorrectedSignal$', '', 'ignorecase');
base = regexprep(base, '_experiment_overview$', '', 'ignorecase');
base = regexprep(base, '\s+', '');
stem = char(base);
end

function b = localBaseName(p)
b = '';
if ~localIsFile(p)
    return;
end
[~, b] = fileparts(p);
end

function rat = localGuessRat(varargin)
rat = '';
expr = '(?i)(Rat\d+)';
for i = 1:nargin
    s = char(varargin{i});
    tok = regexp(s, expr, 'tokens', 'once');
    if ~isempty(tok)
        rat = tok{1};
        return;
    end
end
end

function d = localGuessDate(varargin)
d = '';
expr = '(\d{2}[-_]\d{2}[-_]\d{4}|\d{4}[-_]\d{2}[-_]\d{2})';
for i = 1:nargin
    s = char(varargin{i});
    tok = regexp(s, expr, 'tokens', 'once');
    if ~isempty(tok)
        d = tok{1};
        return;
    end
end
end

function [x, y] = localIntervalTrace(t, z, a, b, includeRight)
if nargin < 5
    includeRight = false;
end
t = double(t(:));
z = double(z(:));
if includeRight
    keep = (t >= a) & (t <= b);
else
    keep = (t >= a) & (t < b);
end
x = t(keep);
y = z(keep);
end

function v = localMeanOrNaN(x)
if isempty(x)
    v = NaN;
else
    v = mean(x, 'omitnan');
    if ~isfinite(v)
        v = NaN;
    end
end
end

function v = localAUCOrNaN(x, y)
if numel(x) < 2 || numel(y) < 2
    v = NaN;
else
    v = trapz(x, y);
    if ~isfinite(v)
        v = NaN;
    end
end
end

function v = localMaxOrBlank(x)
if isempty(x)
    v = NaN;
else
    v = max(x);
    if ~isfinite(v)
        v = NaN;
    end
end
end

function v = localMinOrBlank(x)
if isempty(x)
    v = NaN;
else
    v = min(x);
    if ~isfinite(v)
        v = NaN;
    end
end
end

function lat = localPeakLatencyFromTrace(x, y, t0)
if isempty(x) || isempty(y)
    lat = NaN;
    return;
end
[~, idx] = max(y);
if isempty(idx) || ~isfinite(idx)
    lat = NaN;
else
    lat = x(idx) - t0;
end
end

function lat = localFirstLatency(times, a, b, t0)
times = double(times(:));
keep = times >= a & times < b;
if ~any(keep)
    lat = NaN;
else
    lat = min(times(keep)) - t0;
end
end

%% =====================================================================
% REUSED LOADER HELPERS (kept close to your original overview/export code)
% ======================================================================

function [t, z] = localLoadCorrectedFP(fpMat)
S = load(fpMat);
if isfield(S, 'correctedSignalTable')
    T = S.correctedSignalTable;
    if istable(T)
        if any(strcmp(T.Properties.VariableNames, 'Time_s'))
            t = T.Time_s;
        else
            t = T{:,1};
        end
        if any(strcmp(T.Properties.VariableNames, 'CorrectedSignal'))
            z = T.CorrectedSignal;
        else
            z = T{:,2};
        end
    else
        fn = fieldnames(T);
        if any(strcmp(fn, 'Time_s'))
            t = T.Time_s;
        else
            t = T.(fn{1});
        end
        if any(strcmp(fn, 'CorrectedSignal'))
            z = T.CorrectedSignal;
        else
            z = T.(fn{2});
        end
    end
elseif isfield(S, 'tablediffRelative')
    T = S.tablediffRelative;
    if istable(T)
        if any(strcmp(T.Properties.VariableNames, 'Var1'))
            t = T.Var1;
            z = T.Var2;
        else
            t = T{:,1};
            z = T{:,2};
        end
    else
        t = T(:,1);
        z = T(:,2);
    end
else
    error('Corrected FP MAT does not contain correctedSignalTable or tablediffRelative.');
end
if isrow(t), t = t'; end
if isrow(z), z = z'; end
t = double(t);
z = double(z);
end

function ttl = localParseTTLBox(ttlCsv)
T = readtable(ttlCsv, 'Delimiter', ',', 'ReadVariableNames', false);
if width(T) < 4
    error('TTLBox CSV has unexpected number of columns.');
end
stateCol = T{:,3};
timeCol = T{:,4};
stateStr = lower(strtrim(cellstr(string(stateCol))));
time_s = double(timeCol);
isFalse = strcmp(stateStr, 'false');
isTrue = strcmp(stateStr, 'true');
N = numel(time_s);
starts = [];
widths_ms = [];
for i = 1:(N-1)
    if isFalse(i) && isTrue(i+1)
        w = (time_s(i+1) - time_s(i)) * 1000;
        if w > 0
            starts(end+1,1) = time_s(i); %#ok<AGROW>
            widths_ms(end+1,1) = w; %#ok<AGROW>
        end
    end
end
if isempty(starts)
    ttl.times_s = zeros(0,1);
    ttl.code_ms = zeros(0,1);
    return;
end
starts = starts - starts(1);
targets = [20 40 60 80];
codes = zeros(size(widths_ms));
valid = false(size(widths_ms));
for k = 1:numel(widths_ms)
    [d, idx] = min(abs(widths_ms(k) - targets));
    tgt = targets(idx);
    if d <= 0.05 * tgt
        codes(k) = tgt;
        valid(k) = true;
    end
end
starts = starts(valid);
codes = codes(valid);
ttl.times_s = starts;
ttl.code_ms = codes;
end

function [pks, locs] = localFindPeaks(t, z)
if numel(t) < 5
    pks = [];
    locs = [];
    return;
end
upperBoundController = 1.0;
distanceBetweenPeaksController = 0.0075;
t = t(:);
zRaw = z(:);
zmean = mean(zRaw, 'omitnan');
zstd = std(zRaw, 'omitnan');
upperBound = zmean + (upperBoundController * zstd);
zDet = zRaw - zmean;
dist = distanceBetweenPeaksController * (t(end) - t(1));
if ~isfinite(dist) || dist <= 0
    dist = 0;
end
try
    if dist > 0
        [pks, locs] = findpeaks(zDet, t, 'MinPeakHeight', upperBound, 'MinPeakDistance', dist);
    else
        [pks, locs] = findpeaks(zDet, t, 'MinPeakHeight', upperBound);
    end
catch
    pks = [];
    locs = [];
end
end

function [t, labels] = localLoadUSVCalls(usvMat)
S = load(usvMat);
Calls = [];
fn = fieldnames(S);
for i = 1:numel(fn)
    if strcmpi(fn{i}, 'Calls')
        Calls = S.(fn{i});
        break;
    end
end
if isempty(Calls)
    for i = 1:numel(fn)
        v = S.(fn{i});
        if istable(v) || isstruct(v)
            Calls = v;
            break;
        end
    end
end
if isempty(Calls)
    error('Could not find Calls in USV MAT.');
end
[t, labels] = localExtractTimeAndLabel(Calls);
end

function [t, labels] = localExtractTimeAndLabel(Calls)
labels = {};
if istable(Calls)
    vars = Calls.Properties.VariableNames;
    t = [];
    if any(strcmpi(vars, 'Box'))
        box = Calls.(vars{find(strcmpi(vars, 'Box'),1)});
        t = localBoxToTime(box);
    else
        timeCandidates = vars(contains(lower(string(vars)), 'time'));
        if ~isempty(timeCandidates)
            t = double(Calls.(timeCandidates{1}));
            t = t(:);
        end
    end
    if isempty(t)
        t = zeros(0,1);
    end

    labelCandidates = {'Type','Label','Category','Class','CallType','callType'};
    lab = [];
    for i = 1:numel(labelCandidates)
        idx = find(strcmpi(vars, labelCandidates{i}), 1);
        if ~isempty(idx)
            lab = Calls.(vars{idx});
            break;
        end
    end
    if isempty(lab)
        for i = 1:numel(vars)
            v = Calls.(vars{i});
            if iscategorical(v) || isstring(v) || iscellstr(v)
                lab = v;
                break;
            end
        end
    end
    if isempty(lab)
        labels = repmat({'USV'}, numel(t), 1);
    else
        labels = cellstr(string(lab));
        labels = labels(:);
    end
elseif isstruct(Calls)
    if isfield(Calls, 'Box')
        t = localBoxToTime(Calls.Box);
    elseif isfield(Calls, 'StartTime')
        t = double([Calls.StartTime]');
    elseif isfield(Calls, 'StartTime_s')
        t = double([Calls.StartTime_s]');
    else
        fns = fieldnames(Calls);
        t = [];
        for i = 1:numel(fns)
            if contains(lower(fns{i}), 'time')
                try
                    t = double([Calls.(fns{i})]');
                    break;
                catch
                end
            end
        end
        if isempty(t)
            t = zeros(0,1);
        end
    end

    labelCandidates = {'Type','Label','Category','Class','CallType','callType'};
    labField = '';
    for i = 1:numel(labelCandidates)
        if isfield(Calls, labelCandidates{i})
            labField = labelCandidates{i};
            break;
        end
    end
    if isempty(labField)
        labels = repmat({'USV'}, numel(t), 1);
    else
        tmp = {Calls.(labField)}';
        labels = cellstr(string(tmp));
    end
else
    error('Calls variable has unsupported type.');
end

n = min(numel(t), numel(labels));
t = double(t(1:n));
labels = labels(1:n);
end

function t = localBoxToTime(box)
if isempty(box)
    t = zeros(0,1);
    return;
end
if isnumeric(box)
    if size(box,2) >= 1
        t = double(box(:,1));
    else
        t = zeros(0,1);
    end
    return;
end
if iscell(box)
    t = nan(numel(box),1);
    for i = 1:numel(box)
        try
            b = box{i};
            if isnumeric(b) && ~isempty(b)
                t(i) = double(b(1));
            end
        catch
            t(i) = NaN;
        end
    end
    return;
end
try
    t = double(box(:,1));
catch
    t = zeros(0,1);
end
end

function s = localNormLabel(sIn)
s = lower(string(sIn));
s = strtrim(s);
s = regexprep(s, '[^a-z0-9]', '');
switch char(s)
    case {'miscellaneous','misc','miscallaneous','miscellaneuous'}
        s = "miscellaneuous";
    case {'22khz','22kh','22k','22kilo','22kilohz'}
        s = "22khz";
    case {'flattrill'}
        s = "flattrill";
    case {'multistep','step'}
        % keep 'step' separate only if the exact file uses step; otherwise route later if needed
        if strcmp(char(s),'step')
            s = "stepup"; % broad 'Step' from viewer-style exports maps into Step Up bucket
        else
            s = "multistep";
        end
    case {'trillwithjumps','trilljumps'}
        s = "trillwithjumps";
    case {'invertedu'}
        s = "invertedu";
    case {'complex'}
        s = "complex";
    case {'flat'}
        s = "flat";
    case {'trill'}
        s = "trill";
    case {'ramp','upwardramp'}
        s = "upwardramp";
    otherwise
end
s = char(s);
end

function [a, b] = localReadSyncMapping(syncXlsx)
T = readcell(syncXlsx, 'Sheet', 'sync_mapping');
a = [];
b = [];
for i = 1:size(T,1)
    if size(T,2) < 2
        continue;
    end
    key = lower(char(string(T{i,1})));
    val = T{i,2};
    if contains(key, 'a') && contains(key, 'drift')
        a = str2double(char(string(val)));
    elseif contains(key, 'b') && contains(key, '(s)')
        b = str2double(char(string(val)));
    end
end
if isempty(a) || isnan(a)
    error('Could not read a (drift) from sync_mapping.');
end
if isempty(b) || isnan(b)
    error('Could not read b (s) from sync_mapping.');
end
end
