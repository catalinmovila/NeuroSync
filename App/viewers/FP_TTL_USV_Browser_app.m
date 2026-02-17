function fig = FP_TTL_USV_Browser_app(fpMatPath, ttlCsvPath, usvMatPath, varargin)
% FP_TTL_USV_Browser_v2_6_2
% PASS 2: extra-declustered + heavily commented (student-style).
% ------------------------------------------------------------
% Purpose:
%   Interactive browser for corrected FP with optional TTLBox + USV overlays.
%
% Key behavior (per your requirement):
%   - FP timeline starts at 0 (first FP sample).
%   - TTLBox start-signal (row 1 time) is used as TTL t=0 reference.
%   - TTL "events" are LOW pulses in TTLBox Box15/Box16 style files:
%       each event is a short False interval between long True states,
%       encoded as False->True transitions (2 rows/event).
%     Therefore we plot event time at the False timestamp (pulse start)
%     and duration as (next True - False).
%   - TTL ticks are plotted in the TOP overview as well.
%   - No negative time values are introduced.
%
% Notes:
%   - TTLBox CSV assumed to be the Box15/Box16 export with 5 columns:
%       InputX,?,(True/False),time_s,clock
%     (no header). Time column is column 4.
% ------------------------------------------------------------



%% ---------------- Optional embedding parameters ----------------
% Beginner-style parsing (no inputParser).
% Optional name/value pairs:
%   'Parent'           : graphics container to embed UI into (uitab/uipanel).
%   'AllowFileDialogs' : true/false. If empty, default is:
%                        - standalone (no Parent) => true
%                        - embedded (Parent provided) => false

Parent = [];
allowDialogs = [];

% Read name/value pairs in varargin
if ~isempty(varargin)
    if mod(numel(varargin),2) ~= 0
        error('Optional inputs must be given as name/value pairs.');
    end

    for k = 1:2:numel(varargin)
        optName  = varargin{k};
        optValue = varargin{k+1};

        if isstring(optName) || ischar(optName)
            optName = lower(strtrim(char(optName)));
        else
            error('Optional argument names must be text.');
        end

        if strcmp(optName,'parent')
            Parent = optValue;
        elseif strcmp(optName,'allowfiledialogs')
            allowDialogs = optValue;
        else
            error('Unknown option "%s".', optName);
        end
    end
end

% If user did not specify AllowFileDialogs, decide automatically:
if isempty(allowDialogs)
    allowDialogs = isempty(Parent);
end
%% ---------------- Inputs (app-friendly; popups only if missing) ----------------
if nargin < 1, fpMatPath = ""; end
if nargin < 2, ttlCsvPath = ""; end
if nargin < 3, usvMatPath = ""; end

% Convert inputs to string for consistent checks
fpMatPath  = string(fpMatPath);
ttlCsvPath = string(ttlCsvPath);
usvMatPath = string(usvMatPath);

% FP required
if strlength(fpMatPath)==0 || ~isfile(fpMatPath)
    if ~allowDialogs
        error('Corrected FP MAT not provided.');
    end
    [fpFile, fpPath] = uigetfile({"*.mat","Corrected FP MAT (*.mat)"}, "Select corrected FP MAT");
    % If the user cancels the file picker, return empty figure handle
    if isequal(fpFile, 0)
        fig = [];
        return;
    end
    fpMatPath = string(fullfile(fpPath, fpFile));
end

% TTL optional
if strlength(ttlCsvPath)>0 && ~isfile(ttlCsvPath)
    warning("TTL CSV not found: %s (ignoring)", ttlCsvPath);
    ttlCsvPath = "";
end
if strlength(ttlCsvPath)==0 && allowDialogs
    [ttlFile, ttlPath] = uigetfile({"*.csv","TTLBox CSV (*.csv)"}, "Select TTLBox CSV (optional)");
    if ~isequal(ttlFile,0)
        ttlCsvPath = string(fullfile(ttlPath, ttlFile));
    end
end

% USV optional
if strlength(usvMatPath)>0 && ~isfile(usvMatPath)
    warning("USV MAT not found: %s (ignoring)", usvMatPath);
    usvMatPath = "";
end
if strlength(usvMatPath)==0 && allowDialogs
    [usvFile, usvPath] = uigetfile({"*.mat","DeepSqueak detection MAT (*.mat)"}, "Select DeepSqueak detection MAT (optional)");
    if ~isequal(usvFile,0)
        usvMatPath = string(fullfile(usvPath, usvFile));
    end
end

fpMatPath = char(fpMatPath); ttlCsvPath = char(ttlCsvPath); usvMatPath = char(usvMatPath);
%% ---------------- Load FP ----------------
[tFPraw, yFP] = loadCorrectedFP(fpMatPath);
if isempty(tFPraw) || isempty(yFP)
    error('Corrected FP MAT did not yield usable time/signal vectors.');
end

% Always start FP at 0
tFP = tFPraw - tFPraw(1);
tFP = double(tFP(:));
yFP = double(yFP(:));

% ---------------- Display-only scaling (plots only) ----------------
% Project rule:
%   - yFP stays as saved (raw fraction, ΔF/F).
%   - Only plots use *100 so values are readable.
displayScale = 100;
yFP_plot = yFP * displayScale;


tEnd = max(tFP);
% Safety: if time vector is empty or invalid, force tEnd = 0
if isempty(tEnd) || ~isfinite(tEnd)
    tEnd = 0;
end

%% ---------------- Load TTLBox (optional) ----------------
ttl = struct('t',[],'w',[],'tRefRaw',NaN);
if ~isempty(ttlCsvPath)
    [ttl.t, ttl.w, ttl.tRefRaw] = loadTTLBoxLowPulses_Box15Style(ttlCsvPath);

    if ~isempty(ttl.t)
        tEnd = max(tEnd, max(ttl.t));
    end
end

%% ---------------- Load USV (optional) ----------------
% Loads DeepSqueak Calls table and extracts:
%   - call start times
%   - call category labels (if present)
% Labels are canonicalized to your call-type list.
% NOTE: label 'Noise' is ignored entirely (no toggles / no plots / no counts).

usv = struct('tStart',[], ...
    'label',string.empty(0,1), ...
    'cats',string.empty(0,1), ...
    'byCatTimes',{{}}, ...
    'catColors',zeros(0,3), ...
    'density_t',[], ...
    'density',[], ...
    'density_bin',1, ...
    'autoShifted',false);

if ~isempty(usvMatPath)
    [tS, lab] = loadDeepSqueakStartTimesAndLabels(usvMatPath);

    tS = double(tS(:));
    if isempty(lab)
        lab = repmat("USV", numel(tS), 1);
    else
        lab = string(lab(:));
        if numel(lab) ~= numel(tS)
            lab = repmat("USV", numel(tS), 1);
        end
    end

    % Basic validity
    keep = isfinite(tS) & (tS >= 0);

    % Ignore Noise
    keep = keep & (lower(strtrim(lab)) ~= "noise");

    tS  = tS(keep);
    lab = lab(keep);

    if isempty(lab)
        lab = repmat("USV", numel(tS), 1);
    end

    % Canonicalize labels + build category list in your preferred order
    [labCanon, cats] = canonicalizeUSVLabels(lab);

    usv.tStart = tS;
    usv.label  = labCanon;
    usv.cats   = cats(:);

    % Assign a stable color per category (colors are displayed on the toggles)
    if ~isempty(usv.cats)
        usv.catColors = lines(numel(usv.cats));
        usv.byCatTimes = cell(numel(usv.cats),1);
        for c=1:numel(usv.cats)
            usv.byCatTimes{c} = usv.tStart(usv.label == usv.cats(c));
        end
    end

    if ~isempty(usv.tStart)
        tEnd = max(tEnd, max(usv.tStart));
    end
end

%% ---------------- Build USV density (overview band + bottom strip) ----------------
usv.density_bin = 1.0; % seconds/bin
if ~isempty(usv.tStart)
    [usv.density_t, usv.density] = buildSmoothDensity(usv.tStart, tEnd, usv.density_bin);
else
    usv.density_t = linspace(0, max(tEnd,1), 100);
    usv.density = zeros(size(usv.density_t));
end

%% ---------------- UI layout ----------------
if isempty(Parent)
    fig = uifigure('Name','FP TTL USV Browser (v2.6.2)', 'Position', [100 80 1500 850]);
else
    fig = uipanel(Parent,'BorderType','none','Units','normalized','Position',[0 0 1 1]);
end

uilabel(fig, 'Text','Window (s):', 'Position',[20 820 80 20]);
ddWin  = uidropdown(fig, 'Items', {'2','5','30','60','120','300','600','1200'}, 'Value','120', ...
    'Position',[100 816 90 28]);

uilabel(fig, 'Text','Center time (s):', 'Position',[210 820 95 20]);
edCenter  = uieditfield(fig,'numeric','Value',min(60,tEnd/2), ...
    'Position',[310 816 90 28], 'Limits',[0 max(tEnd,0)+eps]);

cbTTL = uicheckbox(fig,'Text','Show TTL','Value',~isempty(ttl.t), 'Position',[420 820 90 22]);
cbUSV = uicheckbox(fig,'Text','Show USV','Value',~isempty(usv.tStart), 'Position',[520 820 90 22]);

uibutton(fig,'Text','Export (PNG)','Position',[640 816 120 28], 'ButtonPushedFcn',@onExport);

infoLabel = uilabel(fig,'Text','', 'Position',[780 820 700 20]);

axOverview = uiaxes(fig,'Position',[40 520 1420 260]);
title(axOverview,'Overview (click to jump)');
xlabel(axOverview,'Time (s)');
ylabel(axOverview,'Z-Score');
axOverview.Box = 'on';
axOverview.XAxisLocation = 'bottom';


axDetail = uiaxes(fig,'Position',[40 245 1420 265]);
title(axDetail,'Detail Window');
xlabel(axDetail,'Time (s)');
ylabel(axDetail,'Z-Score');
axDetail.Box = 'on';

axDensity = uiaxes(fig,'Position',[40 155 1420 85]);
title(axDensity,'USV call density (overview strip)');
xlabel(axDensity,'Time (s)');
yticks(axDensity,[]);
axDensity.Box = 'on';

% USV category toggles (dynamic: only categories found in the detection file)
% Color-coding is done via checkbox FontColor; label Noise is not included.
catPanel = [];
catCbs   = gobjects(0);
if ~isempty(usv.cats)
    catPanel = uipanel(fig,'Title','USV categories','Position',[40 2 1420 143]);

    nCats = numel(usv.cats);
    nCols = 6;
    nRows = max(3, ceil(nCats / nCols));

    gl = uigridlayout(catPanel,[nRows nCols]);
    % Make the category area usable even if more than 3 rows are required
    if isprop(gl,'Scrollable'); gl.Scrollable = 'on'; end

    gl.RowHeight = repmat({22},1,nRows);
    gl.ColumnWidth = repmat({'1x'},1,nCols);
    gl.Padding = [8 6 8 6];
    gl.RowSpacing = 2;
    gl.ColumnSpacing = 10;

    for c=1:nCats
        cb = uicheckbox(gl,'Text',char(usv.cats(c)),'Value',true);
        cb.FontColor = usv.catColors(c,:);
        cb.ValueChangedFcn = @onAnyChange;
        catCbs(c) = cb;
    end
end


sl = uislider(fig,'Position',[40 800 1420 3], 'Limits',[0 max(tEnd,0)+eps], ...
    'Value', edCenter.Value);

% Hide tick labels on the slider (removes the top ruler text to free vertical space)
if isprop(sl,'MajorTicks');      sl.MajorTicks = []; end
if isprop(sl,'MajorTickLabels'); sl.MajorTickLabels = {}; end
if isprop(sl,'MinorTicks');      sl.MinorTicks = []; end


%% ---------------- Pre-plot Overview ----------------
nMax = 60000;
idx = round(linspace(1, numel(tFP), min(numel(tFP), nMax)));
tFPo = tFP(idx);
yFPo = yFP(idx);

yFPo_plot = yFP_plot(idx);

hOverviewFP = plot(axOverview, tFPo, yFPo_plot, 'LineWidth',1);
hold(axOverview,'on');

% USV density as band at bottom of overview
hOverviewDensity = plotDensityBand(axOverview, usv.density_t, usv.density);

% TTL ticks in overview (by width category)
hOverviewTTL = plotTTLTicksByWidth(axOverview, ttl.t, ttl.w);

yl = ylim(axOverview);
hOverPatch = patch(axOverview, [0 1 1 0], [yl(1) yl(1) yl(2) yl(2)], ...
    [0.8 0.8 0.8], 'FaceAlpha',0.16, 'EdgeColor','none');
uistack(hOverPatch,'bottom');

axOverview.ButtonDownFcn = @onOverviewClick;
hOverviewFP.PickableParts = 'none';
hOverPatch.PickableParts = 'none';

%% ---------------- Density strip (bottom) ----------------
hDenArea = area(axDensity, usv.density_t, usv.density);
hDenArea.FaceColor = [0.10 0.65 0.10];
hDenArea.EdgeColor = 'none';
hDenArea.FaceAlpha = 0.55;
hold(axDensity,'on');
ylim(axDensity,[0 max(usv.density)*1.05 + eps]);

ylD = ylim(axDensity);
hDenPatch = patch(axDensity, [0 1 1 0], [ylD(1) ylD(1) ylD(2) ylD(2)], ...
    [0.7 0.7 0.7], 'FaceAlpha',0.15, 'EdgeColor',[0.3 0.3 0.3], 'LineWidth',1);

%% ---------------- Detail plot objects ----------------
hold(axDetail,'on');
hDetailFP = plot(axDetail, nan, nan, 'LineWidth',1.25);

% TTL colors: 20 ms GREEN per your rule
TTL_COL_20 = [0.10 0.70 0.20];
TTL_COL_40 = [0.85 0.20 0.10];  % 40 ms (avoid blue)
TTL_COL_60 = [0.85 0.20 0.85];
TTL_COL_80 = [0.95 0.55 0.15];

hTTL20 = plot(axDetail, nan, nan, 'Color',TTL_COL_20, 'LineWidth',2.0);
hTTL40 = plot(axDetail, nan, nan, 'Color',TTL_COL_40, 'LineWidth',2.0);
hTTL60 = plot(axDetail, nan, nan, 'Color',TTL_COL_60, 'LineWidth',2.0);
hTTL80 = plot(axDetail, nan, nan, 'Color',TTL_COL_80, 'LineWidth',2.0);

USV_DUMMY_COL  = [0.35 0.35 0.35];
hUSVDummy     = plot(axDetail, nan, nan, 'Color',USV_DUMMY_COL, 'LineWidth',0.75);

% One line object per USV category (legend is kept clean; see toggles for mapping)
hUSVCat = gobjects(numel(usv.cats),1);
for c=1:numel(usv.cats)
    hUSVCat(c) = plot(axDetail, nan, nan, 'Color',usv.catColors(c,:), 'LineWidth',0.90);
    hUSVCat(c).HandleVisibility = 'off';
end

% Legend
hDetailFP.DisplayName = 'FP';
hTTL20.DisplayName    = 'Left lever press (?)';
hTTL40.DisplayName    = 'Right lever press (?)';
hTTL60.DisplayName    = 'Drug reward (?)';
hTTL80.DisplayName    = 'Food reward (?)';
hUSVDummy.DisplayName   = 'USV call start (use category toggles)';
lgd = legend(axDetail,'show','Location','northeastoutside');
lgd.AutoUpdate = 'off';

%% ---------------- Stage markers (split recording into 3) ----------------
tStage1 = tEnd/3;
tStage2 = 2*tEnd/3;

hStageOver1 = xline(axOverview, tStage1, '--', 'Color',[0.25 0.25 0.25], 'LineWidth',2.5);
hStageOver2 = xline(axOverview, tStage2, '--', 'Color',[0.25 0.25 0.25], 'LineWidth',2.5);
hStageDet1  = xline(axDetail,   tStage1, '--', 'Color',[0.25 0.25 0.25], 'LineWidth',2.5);
hStageDet2  = xline(axDetail,   tStage2, '--', 'Color',[0.25 0.25 0.25], 'LineWidth',2.5);
hStageDen1  = xline(axDensity,  tStage1, '--', 'Color',[0.25 0.25 0.25], 'LineWidth',2.5);
hStageDen2  = xline(axDensity,  tStage2, '--', 'Color',[0.25 0.25 0.25], 'LineWidth',2.5);

% keep stage markers out of legends
set([hStageOver1 hStageOver2 hStageDet1 hStageDet2 hStageDen1 hStageDen2], 'HandleVisibility','off');

%% ---------------- Callbacks ----------------
ddWin.ValueChangedFcn    = @onAnyChange;
edCenter.ValueChangedFcn = @onAnyChange;
cbTTL.ValueChangedFcn    = @onAnyChange;
cbUSV.ValueChangedFcn    = @onAnyChange;
sl.ValueChangedFcn       = @onSlider;

%% ---------------- Initial render ----------------
lastCatState = []; % tracks USV category selection state
updateAll();

%% ====================== Nested functions ======================
    function onAnyChange(~,~)
        edCenter.Value = max(0, min(edCenter.Value, tEnd));
        sl.Value = edCenter.Value;
        updateAll();
    end

    function onSlider(~,~)
        edCenter.Value = sl.Value;
        updateAll();
    end

    function onOverviewClick(~, evt)
        ip = evt.IntersectionPoint;
        tClick = ip(1);
        if ~isfinite(tClick); return; end
        tClick = max(0, min(tClick, tEnd));
        edCenter.Value = tClick;
        sl.Value = tClick;
        updateAll();
    end

    function updateAll()
        win = str2double(ddWin.Value);
        % Validate window size (seconds). If invalid, fallback to 120 s.
        if ~isfinite(win) || win <= 0
            win = 120;
        end

        tC = edCenter.Value;
        tA = max(0, tC - win/2);
        tB = min(tEnd, tC + win/2);

	        % Stage indicator (1/3, 2/3, 3/3 of the recording)
	        stageTxt = '';
	        if isfinite(tStage1) && isfinite(tStage2) && tEnd > 0
	            if tC < tStage1
	                stageTxt = ' | Stage: 1/3';
	            elseif tC < tStage2
	                stageTxt = ' | Stage: 2/3';
	            else
	                stageTxt = ' | Stage: 3/3';
	            end
	        end

        nTTL = sum(ttl.t>=tA & ttl.t<=tB);

        % USV category selection (if no category info exists, it behaves as a single 'USV' stream)
        if isempty(catCbs)
            catSel = true;
            showAnyUSV = cbUSV.Value && ~isempty(usv.tStart);
        else
            % Read checkbox states using a simple loop (beginner-friendly)
            catSel = false(size(catCbs));
            for ii = 1:numel(catCbs)
                catSel(ii) = logical(catCbs(ii).Value);
            end
            showAnyUSV = cbUSV.Value && any(catSel) && ~isempty(usv.tStart);
        end

        % Update density only when selection changed (slider movement does NOT recompute density)
        selState = [cbUSV.Value; catSel(:)];
        if ~isequal(selState, lastCatState)
            lastCatState = selState;

            if showAnyUSV
                if isempty(catCbs)
                    tDen = usv.tStart;
                else
                    tDen = vertcat(usv.byCatTimes{catSel});
                end
                [usv.density_t, usv.density] = buildSmoothDensity(tDen, tEnd, usv.density_bin);
            else
                usv.density_t = linspace(0, max(tEnd,1), 100);
                usv.density = zeros(size(usv.density_t));
            end

            % Update density strip
            hDenArea.XData = usv.density_t;
            hDenArea.YData = usv.density;
            ylim(axDensity,[0 max(usv.density)*1.05 + eps]);

            % Update overview density band patch
            updateDensityBandPatch(axOverview, hOverviewDensity, usv.density_t, usv.density);
        end

        % USV counts (selected categories only)
        nUSV = 0;
        nUSVtot = 0;
        if showAnyUSV
            if isempty(catCbs)
                nUSV = sum(usv.tStart>=tA & usv.tStart<=tB);
                nUSVtot = numel(usv.tStart);
            else
                for c=1:numel(usv.cats)
                    if ~catSel(c), continue; end
                    tt = usv.byCatTimes{c};
                    nUSVtot = nUSVtot + numel(tt);
                    nUSV = nUSV + sum(tt>=tA & tt<=tB);
                end
            end
        end

        infoLabel.Text = sprintf('Window: [%.2f %.2f] s | TTL: %d/%d | USV: %d/%d%s', ...
            tA, tB, nTTL, numel(ttl.t), nUSV, nUSVtot, stageTxt );

        % window patches
        yl = ylim(axOverview);
        hOverPatch.XData = [tA tB tB tA];
        hOverPatch.YData = [yl(1) yl(1) yl(2) yl(2)];

        ylD2 = ylim(axDensity);
        hDenPatch.XData = [tA tB tB tA];
        hDenPatch.YData = [ylD2(1) ylD2(1) ylD2(2) ylD2(2)];

        % detail FP
        iA = find(tFP >= tA, 1, 'first'); if isempty(iA); iA=1; end
        iB = find(tFP <= tB, 1, 'last');  if isempty(iB); iB=numel(tFP); end
        hDetailFP.XData = tFP(iA:iB);
        hDetailFP.YData = yFP_plot(iA:iB);
        xlim(axDetail,[tA tB]);

        % detail TTL
        if cbTTL.Value && ~isempty(ttl.t)
            wms = ttl.w * 1000;
            sel = ttl.t>=tA & ttl.t<=tB & isfinite(wms);

            tSel = ttl.t(sel);
            wSel = wms(sel);

            t20 = tSel(abs(wSel-20) <= 1.5);
            t40 = tSel(abs(wSel-40) <= 2.0);
            t60 = tSel(abs(wSel-60) <= 2.5);
            t80 = tSel(abs(wSel-80) <= 3.0);

            [x20,y20] = buildVLines(t20, axDetail);
            [x40,y40] = buildVLines(t40, axDetail);
            [x60,y60] = buildVLines(t60, axDetail);
            [x80,y80] = buildVLines(t80, axDetail);

            hTTL20.XData = x20; hTTL20.YData = y20;
            hTTL40.XData = x40; hTTL40.YData = y40;
            hTTL60.XData = x60; hTTL60.YData = y60;
            hTTL80.XData = x80; hTTL80.YData = y80;
        else
            hTTL20.XData = nan; hTTL20.YData = nan;
            hTTL40.XData = nan; hTTL40.YData = nan;
            hTTL60.XData = nan; hTTL60.YData = nan;
            hTTL80.XData = nan; hTTL80.YData = nan;
        end

        % detail USV (per category)
        if showAnyUSV
            if isempty(catCbs)
                tU = usv.tStart(usv.tStart>=tA & usv.tStart<=tB);
                [xU,yU] = buildVLines(tU, axDetail);
                hUSVDummy.XData = xU; hUSVDummy.YData = yU;
            else
                % hide dummy line (legend handle stays valid)
                hUSVDummy.XData = nan; hUSVDummy.YData = nan;

                for c=1:numel(usv.cats)
                    if catSel(c)
                        tU = usv.byCatTimes{c};
                        tU = tU(tU>=tA & tU<=tB);
                        [xU,yU] = buildVLines(tU, axDetail);
                        hUSVCat(c).XData = xU; hUSVCat(c).YData = yU;
                        hUSVCat(c).Visible = 'on';
                    else
                        hUSVCat(c).XData = nan; hUSVCat(c).YData = nan;
                        hUSVCat(c).Visible = 'off';
                    end
                end
            end
        else
            hUSVDummy.XData = nan; hUSVDummy.YData = nan;
            for c=1:numel(usv.cats)
                hUSVCat(c).XData = nan; hUSVCat(c).YData = nan;
                hUSVCat(c).Visible = 'off';
            end
        end

        % toggles
        setHandlesVisible(hOverviewTTL, cbTTL.Value);
        % Set visibility of hOverviewDensity based on showAnyUSV
        if showAnyUSV
            hOverviewDensity.Visible = 'on';
        else
            hOverviewDensity.Visible = 'off';
        end
        % Set visibility of axDensity based on showAnyUSV
        if showAnyUSV
            axDensity.Visible = 'on';
        else
            axDensity.Visible = 'off';
        end
        if ~isempty(catPanel)
            % Set visibility of catPanel based on cbUSV.Value
            if cbUSV.Value
                catPanel.Visible = 'on';
            else
                catPanel.Visible = 'off';
            end
            catPanel.Enable  = cbUSV.Value;
        end
    end

    function onExport(~,~)
        [outFile, outPath] = uiputfile('*.png','Save PNG');
        if isequal(outFile,0); return; end
        try
            exportgraphics(fig, fullfile(outPath, outFile), 'Resolution', 300);
        catch
            exportapp(ancestor(fig,'figure'), fullfile(outPath, outFile));
        end
    end
end

%% ====================== Helpers ======================


function setHandlesVisible(h, tf)
% setHandlesVisible  Turn Visible on/off for a list of graphics handles.
% -------------------------------------------------------------------------
% This helper is used to hide/show groups of plotted items (for example:
% all TTL tick lines) without writing the same loop many times.
%
% INPUTS
%   h  : graphics handle array (can be empty)
%   tf : true -> visible ON, false -> visible OFF
% -------------------------------------------------------------------------

% If handle list is empty, nothing to do.
if isempty(h)
    return;
end

% Visible property wants text: 'on' or 'off'
vis = 'on';
if ~tf
    vis = 'off';
end

% Apply the visibility setting to each handle, safely.
for k = 1:numel(h)
    if isgraphics(h(k))
        h(k).Visible = vis;
    end
end

end

% (PASS 2) Removed tern() helper to keep code beginner-readable.


function [tFP, yFP] = loadCorrectedFP(matPath)
S = load(matPath);

candNames = {'correctedSignalTable','tablediffRelative','diffRelative','T','dataTable'};
T = [];
for k=1:numel(candNames)
    if isfield(S, candNames{k}) && istable(S.(candNames{k}))
        T = S.(candNames{k}); break;
    end
end
if isempty(T)
    fn = fieldnames(S);
    for k=1:numel(fn)
        if istable(S.(fn{k}))
            T = S.(fn{k}); break;
        end
    end
end
if isempty(T)
    error('Could not find a table in the corrected FP MAT.');
end

timeCandidates = {'Time','time','t','SystemTimestamp','Timestamp','seconds','Seconds'};
tFP = [];
for k=1:numel(timeCandidates)
    idx = find(strcmpi(T.Properties.VariableNames, timeCandidates{k}), 1);
    if ~isempty(idx)
        tFP = T.(T.Properties.VariableNames{idx});
        break;
    end
end
if isempty(tFP)
    tFP = findFirstNumericColumn(T, 1);
end

sigCandidates = {'dFF','dF_F','df_f','Signal','signal','corrected','diffRelative','z','zscore','Z'};
yFP = [];
for k=1:numel(sigCandidates)
    idx = find(strcmpi(T.Properties.VariableNames, sigCandidates{k}), 1);
    if ~isempty(idx)
        yFP = T.(T.Properties.VariableNames{idx});
        break;
    end
end
if isempty(yFP)
    yFP = findFirstNumericColumn(T, 2);
end

tFP = double(tFP(:));
yFP = double(yFP(:));

if isdatetime(tFP)
    tFP = seconds(tFP - tFP(1));
end

[~,ord] = sort(tFP);
tFP = tFP(ord);
yFP = yFP(ord);
end

function col = findFirstNumericColumn(T, which)
numCols = [];
for c=1:width(T)
    v = T{:,c};
    if isnumeric(v) && any(isfinite(v))
        numCols(end+1)=c; %#ok<AGROW>
    end
end
if isempty(numCols)
    error('No usable numeric columns found in corrected FP table.');
end
which = min(which, numel(numCols));
col = T{:, numCols(which)};
end

function [tStartShift, wSec, tRefRaw] = loadTTLBoxLowPulses_Box15Style(csvPath)
% Reads Box15/Box16 TTLBox CSV (no header, 5 columns) and extracts LOW pulses:
%   event time = timestamp where state becomes False,
%   width      = time(next True) - time(False).
%
% Also uses the first timestamp (row 1, col 4) as start-signal reference:
%   tStartShift = tStartRaw - tRefRaw
%
% Output:
%   tStartShift : Nx1 seconds, relative to start-signal (>=0)
%   wSec        : Nx1 pulse width in seconds
%   tRefRaw     : scalar reference time in seconds (raw file time)

% Version-robust read (no header in TTLBox export)
try
    T = readtable(csvPath, 'Delimiter', ',', 'ReadVariableNames', false);
catch
    % Fallback if some options are unsupported in older releases
    T = readtable(csvPath);
end

if width(T) < 4
    error('TTLBox CSV does not have expected columns. Need at least 4 columns.');
end

stateRaw = T{:,3};
tRaw = double(T{:,4});

% Convert state to logical: True=1, False=0
if islogical(stateRaw)
    s = stateRaw;
elseif isnumeric(stateRaw)
    s = stateRaw ~= 0;
else
    sStr = lower(string(stateRaw));
    s = (sStr == "true") | (sStr == "1");
end
s = logical(s(:));
tRaw = double(tRaw(:));

keep = isfinite(tRaw);
tRaw = tRaw(keep);
s = s(keep);

% Sort by time
[~,ord] = sort(tRaw);
tRaw = tRaw(ord);
s = s(ord);

if numel(tRaw) < 3
    tStartShift = []; wSec = []; tRefRaw = NaN; return;
end

% Start-signal reference = first timestamp (row 1)
tRefRaw = tRaw(1);

% LOW pulses are False->True transitions
n = numel(tRaw);
tStart = zeros(n,1);
wSec = zeros(n,1);
k = 0;

for i=1:(n-1)
    if (s(i) == false) && (s(i+1) == true)
        w = tRaw(i+1) - tRaw(i);
        if isfinite(w) && w > 0
            k = k + 1;
            tStart(k,1) = tRaw(i);
            wSec(k,1)   = w;
        end
    end
end

tStart = tStart(1:k);
wSec = wSec(1:k);

% Shift by reference so timeline starts at 0
tStartShift = tStart - tRefRaw;

% Keep non-negative + realistic widths (loose bounds)
keep2 = isfinite(tStartShift) & (tStartShift >= 0) & isfinite(wSec) & (wSec > 0) & (wSec < 2);
tStartShift = tStartShift(keep2);
wSec = wSec(keep2);
end

function [tStart, labels] = loadDeepSqueakStartTimesAndLabels(matPath)
S = load(matPath);
Calls = [];
if isfield(S,'Calls') && istable(S.Calls)
    Calls = S.Calls;
else
    fn = fieldnames(S);
    for k=1:numel(fn)
        if istable(S.(fn{k})) && any(strcmpi(S.(fn{k}).Properties.VariableNames,'Box'))
            Calls = S.(fn{k});
            break;
        end
    end
end
if isempty(Calls) || ~any(strcmpi(Calls.Properties.VariableNames,'Box'))
    error('Could not find DeepSqueak Calls table with a Box column.');
end

% --- start times from Calls.Box(:,1)
Box = Calls.(Calls.Properties.VariableNames{strcmpi(Calls.Properties.VariableNames,'Box')});
if isnumeric(Box)
    B = Box;
elseif iscell(Box)
    try
        B = cell2mat(Box);
    catch
        B = vertcat(Box{:});
    end
elseif istable(Box)
    B = table2array(Box);
else
    error('Unsupported Calls.Box type.');
end

if size(B,2) < 1
    error('Calls.Box does not have expected columns.');
end

tStart = double(B(:,1));

% --- try to locate a label/type column
labels = [];
labelCandidates = {'Type','Label','CallType','Call_Type','callType','Category','Classification', ...
                   'PredictedLabel','Predicted','Prediction','ManualLabel','UserLabel'};

varNames = Calls.Properties.VariableNames;
idx = [];
for k=1:numel(labelCandidates)
    ii = find(strcmpi(varNames, labelCandidates{k}), 1);
    if ~isempty(ii)
        idx = ii;
        break;
    end
end

if ~isempty(idx)
    v = Calls.(varNames{idx});

    if iscategorical(v)
        labels = string(v);
    elseif isstring(v)
        labels = v;
    elseif iscell(v)
        labels = string(v);
    elseif isnumeric(v)
        % numeric labels are uncommon; keep empty and let caller default to 'USV'
        labels = [];
    else
        try
            labels = string(v);
        catch
            labels = [];
        end
    end
end
end

function [tC, dens] = buildSmoothDensity(tStart, tEnd, binSec)
tStart = double(tStart(:));
tStart = tStart(isfinite(tStart));

if nargin < 2 || isempty(tEnd) || ~isfinite(tEnd)
    if isempty(tStart); tEnd = 0; else; tEnd = max(tStart); end
end
tEnd = double(tEnd);

if nargin < 3 || isempty(binSec) || ~isfinite(binSec) || binSec <= 0
    binSec = 1.0;
end
binSec = double(binSec);

if ~isempty(tStart)
    tEnd = max(tEnd, max(tStart));
end
if ~isfinite(tEnd) || tEnd < 0
    tEnd = 0;
end

stop = tEnd + binSec;
if ~isfinite(stop) || stop <= 0
    edges = [0 binSec];
else
    edges = 0:binSec:stop;
    if numel(edges) < 2
        edges = [0 binSec];
    end
end

counts = histcounts(tStart, edges);
tC = edges(1:end-1) + binSec/2;

% Smooth more (less robotic)
wBins = max(5, round(15/binSec));
dens = smoothdata(counts(:), 'gaussian', wBins);

if any(dens > 0)
    p = prctile(dens(dens>0), 99);
else
    p = max(dens) + eps;
end
if isempty(p) || p<=0 || ~isfinite(p)
    p = max(dens) + eps;
end
dens = dens / (p + eps);
dens = min(dens, 1);
end

function updateDensityBandPatch(ax, hBand, tC, dens)
% Updates an existing patch created by plotDensityBand
yl = ylim(ax);
yr = yl(2) - yl(1);
yBase = yl(1) + 0.02*yr;
yTop  = yl(1) + 0.14*yr;

dens = dens(:)';
tC = tC(:)';
y = yBase + (yTop - yBase) * dens;

X = [tC fliplr(tC)];
Y = [yBase*ones(1,numel(tC)) fliplr(y)];

if isgraphics(hBand)
    hBand.XData = X;
    hBand.YData = Y;
end
end

function [labelsOut, catsOrdered] = canonicalizeUSVLabels(labelsIn)
% Maps labels to a canonical set (your provided list) using a tolerant normalizer.
% Any unknown label will be appended as its own category.

labelsIn = string(labelsIn(:));
labelsIn = strtrim(labelsIn);
labelsIn(labelsIn=="") = "USV";

canonical = [ ...
    "Complex"; ...
    "Upward Ramp"; ...
    "Downward Ramp"; ...
    "Flat"; ...
    "Short"; ...
    "Split"; ...
    "Step Up"; ...
    "Step Down"; ...
    "Multi-Step"; ...
    "Trill"; ...
    "Flat-trill"; ...
    "Trill with Jumps"; ...
    "Inverted U"; ...
    "Composite"; ...
    "22-KHz"; ...
    "Unclear"; ...
    "Miscellaneuous"; ...
    "USV" ...
];

canonNorm = normalizeUSVLabel(canonical);
labNorm   = normalizeUSVLabel(labelsIn);

labelsOut = labelsIn;

for i=1:numel(labelsIn)
    % If already exact match to canonical (case-insensitive), keep canonical spelling
    j = find(canonNorm == labNorm(i), 1);
    if ~isempty(j)
        labelsOut(i) = canonical(j);
    else
        % Common alternative spellings
        if labNorm(i) == "miscellaneous"
            labelsOut(i) = "Miscellaneuous";
        elseif labNorm(i) == "flattrill"
            labelsOut(i) = "Flat-trill";
        elseif labNorm(i) == "22khz" || labNorm(i) == "22k"
            labelsOut(i) = "22-KHz";
        end
    end
end

% Categories in your preferred order first, then any remaining unknowns
catsOrdered = string.empty(0,1);
for i=1:numel(canonical)
    if any(labelsOut == canonical(i))
        catsOrdered(end+1,1) = canonical(i); %#ok<AGROW>
    end
end

u = unique(labelsOut,'stable');
for i=1:numel(u)
    if ~any(catsOrdered == u(i))
        catsOrdered(end+1,1) = u(i); %#ok<AGROW>
    end
end
end

function s = normalizeUSVLabel(s)
% Normalizes labels for tolerant matching:
%   - lowercase
%   - trim
%   - remove spaces, underscores, hyphens
%   - remove non-alphanumerics
s = lower(string(s));
s = strtrim(s);
s = replace(s, "_", "");
s = replace(s, "-", "");
s = replace(s, " ", "");
% strip any remaining non-alphanumerics
s = regexprep(s, "[^a-z0-9]", "");
end

function hBand = plotDensityBand(ax, tC, dens)
yl = ylim(ax);
yr = yl(2) - yl(1);
yBase = yl(1) + 0.02*yr;
yTop  = yl(1) + 0.14*yr;

dens = dens(:)';
tC = tC(:)';

y = yBase + (yTop - yBase) * dens;

X = [tC fliplr(tC)];
Y = [yBase*ones(1,numel(tC)) fliplr(y)];
hBand = patch(ax, X, Y, [0.10 0.65 0.10], 'FaceAlpha',0.45, 'EdgeColor','none');
end

function h = plotTTLTicksByWidth(ax, tStart, wSec)
if isempty(tStart) || isempty(wSec)
    h = plot(ax, nan, nan); return;
end

TTL_COL_20 = [0.10 0.70 0.20];
TTL_COL_40 = [0.10 0.40 0.90];
TTL_COL_60 = [0.85 0.20 0.85];
TTL_COL_80 = [0.95 0.55 0.15];
TTL_COL_UNK = [0.20 0.20 0.20];

yl = ylim(ax);
yr = yl(2)-yl(1);
y0 = yl(1) + 0.02*yr;
y1 = yl(1) + 0.16*yr;

wms = wSec(:) * 1000;
tStart = tStart(:);

t20 = tStart(abs(wms-20) <= 1.5);
t40 = tStart(abs(wms-40) <= 2.0);
t60 = tStart(abs(wms-60) <= 2.5);
t80 = tStart(abs(wms-80) <= 3.0);

used = false(size(tStart));
used(abs(wms-20) <= 1.5) = true;
used(abs(wms-40) <= 2.0) = true;
used(abs(wms-60) <= 2.5) = true;
used(abs(wms-80) <= 3.0) = true;
tU = tStart(~used);

h = gobjects(0);
h(end+1) = plotTicks(ax, t20, y0, y1, TTL_COL_20);
h(end+1) = plotTicks(ax, t40, y0, y1, TTL_COL_40);
h(end+1) = plotTicks(ax, t60, y0, y1, TTL_COL_60);
h(end+1) = plotTicks(ax, t80, y0, y1, TTL_COL_80);
h(end+1) = plotTicks(ax, tU , y0, y1, TTL_COL_UNK);
end

function hh = plotTicks(ax, tEvents, y0, y1, col)
if isempty(tEvents)
    hh = plot(ax, nan, nan, 'Color',col, 'LineWidth',1.1);
    return;
end
tEvents = tEvents(:)';
X = reshape([tEvents; tEvents; nan(size(tEvents))], 1, []);
Y = reshape([y0*ones(size(tEvents)); y1*ones(size(tEvents)); nan(size(tEvents))], 1, []);
hh = plot(ax, X, Y, 'Color',col, 'LineWidth',1.1);
end

function [X,Y] = buildVLines(tEvents, ax)
if isempty(tEvents)
    X = nan; Y = nan; return;
end
yl = ylim(ax);
y0 = yl(1); y1 = yl(2);
tEvents = tEvents(:)';
X = reshape([tEvents; tEvents; nan(size(tEvents))], 1, []);
Y = reshape([y0*ones(size(tEvents)); y1*ones(size(tEvents)); nan(size(tEvents))], 1, []);
end