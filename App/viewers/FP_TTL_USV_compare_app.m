function root = FP_TTL_USV_compare_app(exp1, exp2, varargin)
% PASS 2: extra-declustered + heavily commented (student style)
% FP_ded_compare_ultimate
% ------------------------------------------------------------
% Two-experiment FP comparison dashboard (tabbed single window).
%
% What you get:
%   - ONE GUI window with 4 TABS:
%       FULL, SEGMENT 1, SEGMENT 2, SEGMENT 3
%   - Each tab contains TWO stacked plots:
%       TOP:    FP1 (with its TTL + USV overlays)
%       BOTTOM: FP2 (with its TTL + USV overlays)
%   - Each tab also contains the SAME control panel on the right:
%       * Show TTL (FP1)
%       * Show TTL (FP2)
%       * Show USV
%       * Show density band (green)
%       * Per-USV-category toggles (apply to BOTH experiments)
%
% Conventions:
%   - FP time is forced to start at 0 (first FP sample).
%   - TTLBox is optional per experiment. TTL timeline uses FIRST row as
%     start-signal reference (t=0), identical to your FP_ded convention.
%   - USV times are plotted EXACTLY as stored in the DeepSqueak MAT
%     (no shifting / no auto-alignment).
%   - "Noise" labels are ignored.
%
% Notes:
%   - Controls are mirrored across tabs; changing one tab updates all tabs.
%   - Density band is computed from precomputed per-category counts, then
%     recomputed live based on category selection.
%
% Files needed (picked via popup):
%   - Corrected FP MAT (required) for each experiment
%   - TTLBox CSV (optional) for each experiment
%   - DeepSqueak detection MAT (optional) for each experiment
% ------------------------------------------------------------


%% ---------------- Optional embedding parameters ----------------
% Name/value options (simple student style):
%   'Parent'           : container to embed UI into (uitab/uipanel). [] => standalone.
%   'AllowFileDialogs' : true/false. Default: true when standalone, false when embedded.

Parent = [];               % Parent container (when embedded). Empty => standalone figure.
allowDialogs = [];         % Whether uigetfile dialogs are allowed (can be forced by caller).

% -------------------------------
% Read name/value pairs (slow, explicit, beginner style)
% -------------------------------
% We accept:
%   'Parent', <handle>
%   'AllowFileDialogs', true/false
%
% Any other name is ignored (to avoid breaking older calls).
%
if ~isempty(varargin)

    % We expect pairs: name1,value1,name2,value2,...
    % If odd number of inputs is passed, we ignore the last one.
    k = 1;
    while k <= numel(varargin) - 1

        name  = varargin{k};        % option name
        value = varargin{k+1};      % option value

        % Only accept text names
        if ischar(name) || isstring(name)

            % Normalize to lower-case string for comparisons
            nameLower = lower(string(name));

            if nameLower == "parent"
                Parent = value;     % store parent handle

            elseif nameLower == "allowfiledialogs"
                allowDialogs = value;  % store allowDialogs flag

            else
                % Unknown option: ignore (keeps compatibility)
            end
        end

        k = k + 2;  % move to next pair
    end
end

% Default AllowFileDialogs (if caller did not specify it)

if isempty(allowDialogs)
    if isempty(Parent)
        allowDialogs = true;   % standalone app
    else
        allowDialogs = false;  % embedded in a parent container
    end
end

%% ---------------- Select files (FP required; TTL/USV optional) ----------------
% Here we make sure each experiment has at least a corrected FP MAT.
% TTLBox CSV and USV MAT are optional (overlays).
if nargin < 1 || isempty(exp1)
    if allowDialogs
        exp1 = pickExperimentFiles(1);
    else
        error('Experiment 1 inputs were not provided.');
    end
end
if isempty(exp1), root = []; return; end
if nargin < 2 || isempty(exp2)
    if allowDialogs
        exp2 = pickExperimentFiles(2);
    else
        error('Experiment 2 inputs were not provided.');
    end
end
if isempty(exp2), root = []; return; end

%% ---------------- Load experiments ----------------
% Load data for each experiment into a single struct:
%   E.fp (time + signal), E.ttl (events), E.usv (calls), etc.
E1 = loadExperiment(exp1.fpMatPath, exp1.ttlCsvPath, exp1.usvMatPath, 'FP1');
E2 = loadExperiment(exp2.fpMatPath, exp2.ttlCsvPath, exp2.usvMatPath, 'FP2');

%% ---------------- Union USV categories + consistent colors ----------------
[catsUnion, catColors] = buildUnionCategories(E1.usv, E2.usv);
E1.usv = mapUSVtoUnion(E1.usv, catsUnion);
E2.usv = mapUSVtoUnion(E2.usv, catsUnion);

%% ---------------- Precompute density bins (per experiment, per union category) ----------------
binSec = 1.0; % seconds/bin
E1.usv = precomputeDensityCounts(E1.usv, E1.tEndAll, catsUnion, binSec);
E2.usv = precomputeDensityCounts(E2.usv, E2.tEndAll, catsUnion, binSec);

%% ---------------- Views ----------------
ttlCfg = defaultTTLCfg();
views = buildViews(E1, E2);

%% ---------------- Build TABBED UI ----------------
% Create a single window (or embed in Parent) with 4 tabs.
% Each tab shows top plot for EXP1 and bottom plot for EXP2.
% Right side has toggles which are mirrored across tabs.
app = struct();
app.E1 = E1;
app.E2 = E2;
app.views = views;
app.catsUnion = catsUnion;
app.catColors = catColors;
app.binSec = binSec;
app.ttlCfg = ttlCfg;

% Global state (mirrored across all tabs)
app.state.showTTL1 = ~isempty(E1.ttl.tStart);
app.state.showTTL2 = ~isempty(E2.ttl.tStart);
app.state.showUSV  = (~isempty(E1.usv.tStart) || ~isempty(E2.usv.tStart));
app.state.catSel   = true(numel(catsUnion),1);
app.state.showDens = app.state.showUSV;

app.isSyncing = false;

% Root container (standalone or embedded)
if isempty(Parent)
    app.root = uifigure('Name','FP Compare Ultimate (2 experiments)', 'Position',[80 60 1650 920]);
else
    app.root = uipanel(Parent,'BorderType','none','Units','normalized','Position',[0 0 1 1]);
end
root = app.root;

% Tab group fills root
app.tg  = uitabgroup(app.root, 'Units','normalized', 'Position',[0 0 1 1]);
nViews = numel(views);
app.tabs = gobjects(nViews,1);
app.axTop = gobjects(nViews,1);
app.axBot = gobjects(nViews,1);
app.plotPanels = gobjects(nViews,1);
% Controls are stored as a CELL array because each element contains a struct
% of UI handles. Preallocating as an empty struct array (struct()) causes
% "Subscripted assignment between dissimilar structures" on the first fill.
app.ctrl = cell(1, nViews);

% Keep listeners alive (for auto-refreshing overlays when YLim changes)
app.limListeners = cell(nViews,2);


% Store plotted handle bundles for quick visibility updates
app.plotH = repmat(struct('ax1',[],'ax2',[]), nViews, 1);

% Initial limits for reset
app.initXLim = cell(nViews,2);
app.initYLim = cell(nViews,2);

for v = 1:nViews
    app.tabs(v) = uitab(app.tg, 'Title', views(v).title);

    % Layout: plots left, controls right
    gl = uigridlayout(app.tabs(v), [1 2]);
    gl.ColumnWidth = {'1x', 380};
    gl.RowHeight   = {'1x'};
    gl.Padding     = [8 8 8 8];
    gl.ColumnSpacing = 10;

    plotPanel = uipanel(gl, 'Title','');
    plotPanel.BorderType = 'none';
    app.plotPanels(v) = plotPanel;

    plotGL = uigridlayout(plotPanel, [2 1]);
    plotGL.RowHeight = {'1x','1x'};
    plotGL.ColumnWidth = {'1x'};
    plotGL.Padding = [6 6 6 6];
    plotGL.RowSpacing = 10;

    ax1 = uiaxes(plotGL);
    ax2 = uiaxes(plotGL);
    setupAxis(ax1);
    setupAxis(ax2);

    % Plot with overlays
    app.plotH(v).ax1 = plotOneAxis(ax1, E1, views(v).tA1, views(v).tB1, catsUnion, catColors, ttlCfg, sprintf('FP1: %s', E1.label), views(v));
    app.plotH(v).ax2 = plotOneAxis(ax2, E2, views(v).tA2, views(v).tB2, catsUnion, catColors, ttlCfg, sprintf('FP2: %s', E2.label), views(v));

    % Reduce clutter: X label only on bottom axis
    ax1.XLabel.String = '';
    xlabel(ax1,'');

    % NOTE: Axes are intentionally NOT linked.
    % This lets you zoom/pan FP1 and FP2 independently (per your request).

    % Store init limits
    app.initXLim{v,1} = xlim(ax1);
    app.initYLim{v,1} = ylim(ax1);
    app.initXLim{v,2} = xlim(ax2);
    app.initYLim{v,2} = ylim(ax2);

    app.axTop(v) = ax1;
    app.axBot(v) = ax2;

    % Auto-refresh overlays (TTL/USV vlines + density band) when YLim changes
    try
        app.limListeners{v,1} = addlistener(ax1, 'YLim', 'PostSet', @(~,~)onAxisYLimChanged(v,1));
        app.limListeners{v,2} = addlistener(ax2, 'YLim', 'PostSet', @(~,~)onAxisYLimChanged(v,2));
    catch
    end

    % Controls panel
    ctrlPanel = uipanel(gl, 'Title','Controls');
    app.ctrl{v} = buildControls(ctrlPanel, v);

end

% Apply initial state to UI + plots
syncControlsAndInfo();
applyVisibility();

%% ---------------- Nested callbacks ----------------
    function setupAxis(ax)
        ax.Box = 'on';
        ax.XGrid = 'on';
        ax.YGrid = 'on';
        ax.FontSize = 10;
        ax.NextPlot = 'add';
    end

    function ctrl = buildControls(parentPanel, viewIdx)
        % Returns a struct of uicontrol handles for one tab.
        ctrl = struct();

        % Rows:
        %  1-4  : visibility toggles
        %  5    : buttons
        %  6    : TTL legend (pulse width -> meaning)
        %  7    : USV label
        %  8    : USV category scroller
        %  9    : info
        glc = uigridlayout(parentPanel, [9 1]);
        glc.RowHeight = {26,26,26,26,30,120,18,'1x',22};
        glc.ColumnWidth = {'1x'};
        glc.Padding = [10 10 10 10];
        glc.RowSpacing = 8;

        ctrl.cbTTL1 = uicheckbox(glc, 'Text','Show TTL (FP1)', 'Tag','cbTTL1', 'Value', app.state.showTTL1);
        ctrl.cbTTL2 = uicheckbox(glc, 'Text','Show TTL (FP2)', 'Tag','cbTTL2', 'Value', app.state.showTTL2);
        ctrl.cbUSV  = uicheckbox(glc, 'Text','Show USV',      'Tag','cbUSV',  'Value', app.state.showUSV);
        ctrl.cbDens = uicheckbox(glc, 'Text','Show density band', 'Tag','cbDens', 'Value', app.state.showDens);

        btnRow = uigridlayout(glc, [1 3]);
        btnRow.RowHeight = {30};
        btnRow.ColumnWidth = {'1x','1x','1x'};
        btnRow.Padding = [0 0 0 0];
        btnRow.ColumnSpacing = 8;

        ctrl.btnReset   = uibutton(btnRow, 'Text','Reset view', 'Tag','btnReset');
        ctrl.btnRefresh = uibutton(btnRow, 'Text','Refresh overlays', 'Tag','btnRefresh');
        ctrl.btnExport  = uibutton(btnRow, 'Text','Export PNGs', 'Tag','btnExport');

        % TTL legend under the toggles: pulse width -> event meaning
        ctrl.ttlLegendPanel = buildTTLLegendUI(glc);

        uilabel(glc, 'Text','USV categories (apply to BOTH):', 'FontWeight','bold');

        catHolder = uipanel(glc, 'Title','');
        catHolder.BorderType = 'none';
        catGL = uigridlayout(catHolder, [1 1]);
        catGL.Padding = [0 0 0 0];
        if isprop(catGL,'Scrollable'); catGL.Scrollable = 'on'; end

        nCats = numel(app.catsUnion);
        ctrl.catCbs = gobjects(nCats,1);

        if nCats == 0
            uilabel(catGL, 'Text','(No USV categories found)', 'FontAngle','italic');
        else
            nCols = 2;
            nRows = max(3, ceil(nCats / nCols));
            cgrid = uigridlayout(catGL, [nRows nCols]);
            if isprop(cgrid,'Scrollable'); cgrid.Scrollable = 'on'; end
            cgrid.RowHeight = repmat({22}, 1, nRows);
            cgrid.ColumnWidth = repmat({'1x'}, 1, nCols);
            cgrid.RowSpacing = 4;
            cgrid.ColumnSpacing = 10;
            cgrid.Padding = [2 2 2 2];

            for i = 1:nCats
                cb = uicheckbox(cgrid, 'Text', char(app.catsUnion(i)), 'Value', true);
                cb.Tag = sprintf('cat_%d', i);
                cb.FontColor = app.catColors(i,:);
                ctrl.catCbs(i) = cb;
            end
        end

        ctrl.info = uilabel(glc, 'Text','', 'FontColor',[0.2 0.2 0.2]);

        % Hook callbacks
        ctrl.cbTTL1.ValueChangedFcn = @onAnyChange;
        ctrl.cbTTL2.ValueChangedFcn = @onAnyChange;
        ctrl.cbUSV.ValueChangedFcn  = @onAnyChange;
        ctrl.cbDens.ValueChangedFcn = @onAnyChange;

        for i = 1:numel(ctrl.catCbs)
            if isgraphics(ctrl.catCbs(i))
                ctrl.catCbs(i).ValueChangedFcn = @onAnyChange;
            end
        end

        ctrl.btnReset.ButtonPushedFcn   = @(~,~)onReset(viewIdx);
        ctrl.btnRefresh.ButtonPushedFcn = @(~,~)onRefresh();
        ctrl.btnExport.ButtonPushedFcn  = @(~,~)onExportAll();
    end

    function ttlPanel = buildTTLLegendUI(parentGL)
        % Small legend under the TTL toggles so you can immediately see
        % what 20/40/60/80 ms means (matching your older FP_ded script).
        ttlPanel = uipanel(parentGL, 'Title','TTL meaning (pulse width)', 'FontWeight','bold');
        ttlPanel.BorderType = 'etchedin';

        hasAnyTTL = ~isempty(app.E1.ttl.tStart) || ~isempty(app.E2.ttl.tStart);

        gl = uigridlayout(ttlPanel, [1 1]);
        gl.Padding = [6 6 6 6];
        gl.RowSpacing = 4;
        gl.ColumnSpacing = 6;

        if ~hasAnyTTL
            uilabel(gl, 'Text','(No TTL loaded)', 'FontAngle','italic', 'FontColor',[0.35 0.35 0.35]);
            return;
        end

        n = numel(ttlCfg.codesMs);
        % Add one extra row for "unknown".
        rows = n + 1;
        g2 = uigridlayout(gl, [rows 3]);
        g2.RowHeight = repmat({18}, 1, rows);
        g2.ColumnWidth = {38, 42, '1x'};
        g2.Padding = [0 0 0 0];
        g2.RowSpacing = 4;
        g2.ColumnSpacing = 6;

        % Known TTLs
        for k = 1:n
            % Color swatch
            sw = uipanel(g2);
            sw.BorderType = 'none';
            sw.BackgroundColor = ttlCfg.colors(k,:);

            uilabel(g2, 'Text', sprintf('%d ms', ttlCfg.codesMs(k)), 'HorizontalAlignment','left');
            uilabel(g2, 'Text', ttlCfg.labels{k}, 'HorizontalAlignment','left');
        end

        % Unknown
        sw = uipanel(g2);
        sw.BorderType = 'none';
        sw.BackgroundColor = ttlCfg.unknownColor;
        uilabel(g2, 'Text', 'other', 'HorizontalAlignment','left');
        uilabel(g2, 'Text', 'Unknown TTL width', 'HorizontalAlignment','left');
    end

    function onAnyChange(src, ~)
        if app.isSyncing
            return;
        end

        tag = '';
        try
            tag = char(src.Tag);
        catch
        end

        % Update global state from the triggering control
        switch tag
            case 'cbTTL1'
                app.state.showTTL1 = logical(src.Value);
            case 'cbTTL2'
                app.state.showTTL2 = logical(src.Value);
            case 'cbUSV'
                app.state.showUSV = logical(src.Value);
            case 'cbDens'
                app.state.showDens = logical(src.Value);
            otherwise
                if startsWith(string(tag), "cat_")
                    idx = sscanf(tag, 'cat_%d');
                    if ~isempty(idx) && idx>=1 && idx<=numel(app.state.catSel)
                        app.state.catSel(idx) = logical(src.Value);
                    end
                end
        end

        % Enforce density rules
        if ~app.state.showUSV || ~any(app.state.catSel)
            app.state.showDens = false;
        end

        syncControlsAndInfo();
        applyVisibility();
    end

    function syncControlsAndInfo()
        app.isSyncing = true;

        nCats = numel(app.catsUnion);
        nSel = sum(app.state.catSel);

        for v2 = 1:numel(app.ctrl)
            c = app.ctrl{v2};

            % TTL availability
            if isempty(app.E1.ttl.tStart)
                c.cbTTL1.Value = false;
                c.cbTTL1.Enable = 'off';
            else
                c.cbTTL1.Enable = 'on';
                c.cbTTL1.Value = app.state.showTTL1;
            end
            if isempty(app.E2.ttl.tStart)
                c.cbTTL2.Value = false;
                c.cbTTL2.Enable = 'off';
            else
                c.cbTTL2.Enable = 'on';
                c.cbTTL2.Value = app.state.showTTL2;
            end

            % USV availability
            if ~(~isempty(app.E1.usv.tStart) || ~isempty(app.E2.usv.tStart))
                c.cbUSV.Value = false;
                c.cbUSV.Enable = 'off';
                c.cbDens.Value = false;
                c.cbDens.Enable = 'off';
            else
                c.cbUSV.Enable = 'on';
                c.cbUSV.Value = app.state.showUSV;

                if app.state.showUSV && any(app.state.catSel)
                    c.cbDens.Enable = 'on';
                else
                    c.cbDens.Enable = 'off';
                end
                c.cbDens.Value = app.state.showDens;
            end

            % Category checkboxes
            for i = 1:numel(c.catCbs)
                if ~isgraphics(c.catCbs(i)); continue; end
                c.catCbs(i).Value = app.state.catSel(i);
                % Enable/disable category checkboxes based on Show USV
                if app.state.showUSV
                    c.catCbs(i).Enable = 'on';
                else
                    c.catCbs(i).Enable = 'off';
                end
            end

            % Info text
            if nCats == 0
                c.info.Text = 'USV categories: (none found)';
            else
                c.info.Text = sprintf('USV categories selected: %d / %d', nSel, nCats);
            end
        end

        app.isSyncing = false;
    end
    function applyVisibility()
        showTTL1 = logical(app.state.showTTL1);
        showTTL2 = logical(app.state.showTTL2);
        showUSV  = logical(app.state.showUSV);
        catSel   = logical(app.state.catSel(:));

        showDens = logical(app.state.showDens);
        if ~showUSV || ~any(catSel)
            showDens = false;
        end

        % TTL visibility
        for v3 = 1:numel(app.plotH)
            setHandlesVisible(app.plotH(v3).ax1.ttlHandles, showTTL1);
            setHandlesVisible(app.plotH(v3).ax2.ttlHandles, showTTL2);
        end

        % USV category visibility
        for v3 = 1:numel(app.plotH)
            for c = 1:numel(app.catsUnion)
                tf = showUSV && catSel(c);
                setHandleVisibleSafe(app.plotH(v3).ax1.usvCat(c), tf);
                setHandleVisibleSafe(app.plotH(v3).ax2.usvCat(c), tf);
            end
        end

        % Density (compute once per experiment)
        if showDens
            [tC1, dens1] = densityFromCounts(app.E1.usv.densityCounts, app.E1.usv.densityEdges, app.binSec, catSel);
            [tC2, dens2] = densityFromCounts(app.E2.usv.densityCounts, app.E2.usv.densityEdges, app.binSec, catSel);
        else
            tC1 = app.E1.usv.densityCenters; dens1 = zeros(size(tC1));
            tC2 = app.E2.usv.densityCenters; dens2 = zeros(size(tC2));
        end

        % Cache density so YLim listeners can reposition the band instantly
        app.cache = struct('showDens',showDens,'tC1',tC1,'dens1',dens1,'tC2',tC2,'dens2',dens2);

        for v3 = 1:numel(app.plotH)
            setHandleVisibleSafe(app.plotH(v3).ax1.denPatch, showDens);
            setHandleVisibleSafe(app.plotH(v3).ax2.denPatch, showDens);
            if showDens
                updateDensityBandPatch(app.plotH(v3).ax1.ax, app.plotH(v3).ax1.denPatch, tC1, dens1);
                updateDensityBandPatch(app.plotH(v3).ax2.ax, app.plotH(v3).ax2.denPatch, tC2, dens2);
            end
        end

        % IMPORTANT: Refresh vline YData to match current YLim
        % (otherwise TTL/USV lines look "cut off" after Y-zoom/pan)
        refreshAllOverlays();
    end

    function onRefresh()
        applyVisibility();
    end

    function onReset(viewIdx)
        try
            if viewIdx < 1 || viewIdx > numel(app.views)
                return;
            end

            ax1 = app.axTop(viewIdx);
            ax2 = app.axBot(viewIdx);

            % Reset X-limits to the view window
            if isgraphics(ax1)
                xlim(ax1, [app.views(viewIdx).tA1 app.views(viewIdx).tB1]);
                ylim(ax1, robustYLim(app.E1.tFP, app.E1.yFP_plot, app.views(viewIdx).tA1, app.views(viewIdx).tB1));
            end
            if isgraphics(ax2)
                xlim(ax2, [app.views(viewIdx).tA2 app.views(viewIdx).tB2]);
                ylim(ax2, robustYLim(app.E2.tFP, app.E2.yFP_plot, app.views(viewIdx).tA2, app.views(viewIdx).tB2));
            end

            applyVisibility();
            refreshAxisOverlays(viewIdx,1);
            refreshAxisOverlays(viewIdx,2);
        catch
        end
    end

    function yl = robustYLim(t, y, tA, tB)
        % Robust ylim from data in [tA,tB], avoids degenerate [0 0] resets.
        % Uses percentiles so a single artifact spike doesn't blow up the axis.
        try
            idx = (t >= tA) & (t <= tB) & isfinite(y);
            yy = double(y(idx));
            if isempty(yy)
                yl = [-1 1];
                return;
            end

            lo = prctile(yy, 1);
            hi = prctile(yy, 99);
            if ~isfinite(lo) || ~isfinite(hi) || lo == hi
                lo = min(yy);
                hi = max(yy);
            end

            r = hi - lo;
            if ~isfinite(r) || r <= 0
                r = max(abs(yy)) + eps;
                lo = -r; hi = r;
            end

            pad = 0.12 * r;
            yl = [lo - pad, hi + pad];
        catch
            yl = [-1 1];
        end
    end

    function onExportAll()
        try
            outDir = uigetdir(pwd, 'Select folder to export PNGs (one per tab)');
            if isequal(outDir,0)
                return;
            end
        catch
            outDir = pwd;
        end

        for v4 = 1:numel(app.views)
            try
                % Make sure the tab is visible before exporting
                app.tg.SelectedTab = app.tabs(v4);
                drawnow;

                base = regexprep(app.views(v4).title, '[^a-zA-Z0-9\-_ ]', '');
                base = strtrim(base);
                if isempty(base); base = sprintf('view_%d', v4); end

                fn = fullfile(outDir, sprintf('%s.png', base));

                % Export only the plot panel (no controls)
                exportgraphics(app.plotPanels(v4), fn, 'Resolution', 200);
            catch
                % ignore per-tab failures
            end
        end

        disp('Export complete.');
    end

    function onAxisYLimChanged(viewIdx, whichAxis)
        % Keeps TTL/USV vertical lines + density band spanning the full plot height
        % after zoom/pan changes the Y-limits.
        try
            if app.isSyncing
                return;
            end
            refreshAxisOverlays(viewIdx, whichAxis);
        catch
        end
    end

    function refreshAllOverlays()
        % Updates overlays in all tabs/axes
        for vv = 1:numel(app.plotH)
            refreshAxisOverlays(vv, 1);
            refreshAxisOverlays(vv, 2);
        end
    end

    function refreshAxisOverlays(viewIdx, whichAxis)
        % Refresh TTL/USV vertical lines (and density band position) for one axis.
        if viewIdx < 1 || viewIdx > numel(app.plotH)
            return;
        end

        if whichAxis == 1
            B = app.plotH(viewIdx).ax1;
            isExp1 = true;
        else
            B = app.plotH(viewIdx).ax2;
            isExp1 = false;
        end

        if ~isstruct(B) || ~isfield(B,'ax') || ~isgraphics(B.ax)
            return;
        end

        yl = ylim(B.ax);

        % TTL line segments
        if isfield(B,'ttlHandles') && ~isempty(B.ttlHandles) && isfield(B,'ttlTimes')
            for k = 1:numel(B.ttlHandles)
                if ~isgraphics(B.ttlHandles(k)); continue; end
                tEv = [];
                if iscell(B.ttlTimes) && numel(B.ttlTimes) >= k
                    tEv = B.ttlTimes{k};
                end
                [X,Y] = buildVLines(tEv, yl);
                try
                    set(B.ttlHandles(k), 'XData', X, 'YData', Y);
                catch
                end
            end
        end

        % USV line segments (per category)
        if isfield(B,'usvCat') && ~isempty(B.usvCat) && isfield(B,'usvTimes')
            for c = 1:numel(B.usvCat)
                if ~isgraphics(B.usvCat(c)); continue; end
                tEv = [];
                if iscell(B.usvTimes) && numel(B.usvTimes) >= c
                    tEv = B.usvTimes{c};
                end
                [X,Y] = buildVLines(tEv, yl);
                try
                    set(B.usvCat(c), 'XData', X, 'YData', Y);
                catch
                end
            end
        end

        % Density band position depends on current YLim
        if isfield(B,'denPatch') && isgraphics(B.denPatch)
            try
                if isfield(app,'cache') && isfield(app.cache,'showDens') && app.cache.showDens
                    if isExp1
                        updateDensityBandPatch(B.ax, B.denPatch, app.cache.tC1, app.cache.dens1);
                    else
                        updateDensityBandPatch(B.ax, B.denPatch, app.cache.tC2, app.cache.dens2);
                    end
                else
                    if isExp1
                        updateDensityBandPatch(B.ax, B.denPatch, app.E1.usv.densityCenters, zeros(size(app.E1.usv.densityCenters)));
                    else
                        updateDensityBandPatch(B.ax, B.denPatch, app.E2.usv.densityCenters, zeros(size(app.E2.usv.densityCenters)));
                    end
                end
            catch
            end
        end
    end

end

%% ========================= Plotting helpers =========================

function out = plotOneAxis(ax, E, tA, tB, catsUnion, catColors, ttlCfg, axisTitle, view)

out = struct('ax',ax,'ttlHandles',gobjects(0),'ttlTimes',[],'usvCat',gobjects(0),'usvTimes',[],'denPatch',[]);

out.ttlTimes = cell(0,1);
out.usvTimes = cell(numel(catsUnion),1);

% Guard: if no data in window
idx = (E.tFP >= tA) & (E.tFP <= tB);
if ~any(idx)
    plot(ax, nan, nan);
    title(ax, [axisTitle ' (no FP in window)']);
    return;
end

plot(ax, E.tFP(idx), E.yFP_plot(idx), 'LineWidth', 1.15);
grid(ax,'on');
box(ax,'on');
xlabel(ax,'Time (s)');
ylabel(ax,'Z-Score');
title(ax, axisTitle, 'Interpreter','none');
xlim(ax, [tA tB]);

% Stage markers (1/3 and 2/3 of this experiment)
try
    addStageMarker(ax, E.b1, [0.25 0.25 0.25]);
    addStageMarker(ax, E.b2, [0.25 0.25 0.25]);
catch
end

% TTL (by width category)
[out.ttlHandles, out.ttlTimes] = plotTTLLines(ax, E.ttl, tA, tB, ttlCfg);

% USV category lines (1 object per category)
out.usvCat = gobjects(numel(catsUnion),1);
out.usvTimes = cell(numel(catsUnion),1);
yl = ylim(ax);
for c = 1:numel(catsUnion)
    tEv = E.usv.byUnionCat{c};
    tEv = tEv(tEv>=tA & tEv<=tB);
    out.usvTimes{c} = tEv;
    [X,Y] = buildVLines(tEv, yl);
    out.usvCat(c) = plot(ax, X, Y, 'Color', catColors(c,:), 'LineWidth', 0.85);
    out.usvCat(c).HandleVisibility = 'off';
end

% Density band (thin, inside axis)
hold(ax,'on');
out.denPatch = plotDensityBand(ax, E.usv.densityCenters, zeros(size(E.usv.densityCenters)));
out.denPatch.HandleVisibility = 'off';
% Keep the density band behind lines/FP
try
    uistack(out.denPatch,'bottom');
catch
end
hold(ax,'off');

% Legend: FP + TTL meanings only (USV controlled via toggles)
try
    makeSimpleLegend(ax, ttlCfg);
catch
end

% View subtitle in XLabel (helps interpretation)
try
    if isfield(view,'subtitle') && ~isempty(view.subtitle)
        ax.XLabel.String = sprintf('Time (s)  |  %s', view.subtitle);
    end
catch
end

end

function makeSimpleLegend(ax, ttlCfg)
hold(ax,'on');
h = gobjects(0); lab = {};

% FP dummy
h(end+1) = plot(ax, nan, nan, 'k-', 'LineWidth', 1.15); %#ok<AGROW>
lab{end+1} = 'Z-Score'; %#ok<AGROW>

for k=1:numel(ttlCfg.colors)
    h(end+1) = plot(ax, nan, nan, '-', 'Color', ttlCfg.colors(k,:), 'LineWidth', ttlCfg.lineWidth); %#ok<AGROW>
    lab{end+1} = ttlCfg.labels{k}; %#ok<AGROW>
end

legend(ax, h, lab, 'Location','northeast');
hold(ax,'off');
end

function addStageMarker(ax, x, col)
if ~isfinite(x); return; end

if exist('xline','file') == 2
    h = xline(ax, x, '--');
    set(h,'Color',col,'LineWidth',2.2,'HandleVisibility','off');
else
    yl = ylim(ax);
    line(ax, [x x], yl, 'Color',col,'LineStyle','--','LineWidth',2.2,'HandleVisibility','off');
end
end

function [hTTL, timesByType] = plotTTLLines(ax, ttl, tA, tB, ttlCfg)
% Returns an array of line handles (4 types + unknown)
hTTL = gobjects(0);
nTypes = numel(ttlCfg.codesMs);
timesByType = cell(nTypes+1,1);
if isempty(ttl.tStart)
    return;
end

yl = ylim(ax);

% Known widths
for k = 1:numel(ttlCfg.codesMs)
    sel = (ttl.typeIdx == k) & (ttl.tStart >= tA) & (ttl.tStart <= tB);
    tEv = ttl.tStart(sel);
    timesByType{k} = tEv;
    [X,Y] = buildVLines(tEv, yl);
    hh = plot(ax, X, Y, 'Color', ttlCfg.colors(k,:), 'LineWidth', ttlCfg.lineWidth);
    hh.HandleVisibility = 'off';
    hTTL(end+1) = hh; %#ok<AGROW>
end

% Unknown
selU = isnan(ttl.typeIdx) & (ttl.tStart >= tA) & (ttl.tStart <= tB);
tEv = ttl.tStart(selU);
timesByType{end} = tEv;
[X,Y] = buildVLines(tEv, yl);
hh = plot(ax, X, Y, 'Color', ttlCfg.unknownColor, 'LineWidth', ttlCfg.lineWidth);
hh.HandleVisibility = 'off';
hTTL(end+1) = hh;

end

function [X,Y] = buildVLines(tEvents, yLim)
% Returns NaN-separated vertical line segments spanning yLim
if isempty(tEvents)
    X = nan; Y = nan; return;
end
t = tEvents(:)';
y0 = yLim(1); y1 = yLim(2);
X = reshape([t; t; nan(size(t))], 1, []);
Y = reshape([y0*ones(size(t)); y1*ones(size(t)); nan(size(t))], 1, []);
end

function ttlCfg = defaultTTLCfg()
ttlCfg = struct();
ttlCfg.codesMs = [20 40 60 80];
ttlCfg.tolPct  = 0.10;
ttlCfg.lineWidth = 2.0;

% Meanings from your FP_ded script (Box15 convention)
ttlCfg.labels = { ...
    'Left lever press (20 ms)', ...
    'Right lever press (40 ms)', ...
    'Drug reward (60 ms)', ...
    'Food reward (80 ms)' ...
};

% Keep 20 ms GREEN; avoid blues near FP
ttlCfg.colors = [ ...
    0.10 0.70 0.20; ... % 20 ms
    0.85 0.20 0.10; ... % 40 ms
    0.85 0.20 0.85; ... % 60 ms
    0.95 0.55 0.15  ... % 80 ms
];

ttlCfg.unknownColor = [0.55 0.55 0.55];
end

%% ========================= Experiment loading =========================

function exp = pickExperimentFiles(iExp)
exp = [];

titleFP  = sprintf('Select CORRECTED photometry MAT for FP%d (required)', iExp);
titleTTL = sprintf('Select TTLBox CSV for FP%d (optional) - Cancel to skip', iExp);
titleUSV = sprintf('Select DeepSqueak detection MAT for FP%d (optional) - Cancel to skip', iExp);

% Use a 2-row filter (works across MATLAB versions; avoids "Invalid file filter" warnings)
[fpName, fpPath] = uigetfile({
    '*_CorrectedSignal.mat','Corrected photometry MAT (*_CorrectedSignal.mat)';
    '*.mat','MAT files (*.mat)'
    }, titleFP);
if isequal(fpName,0)
    disp('Cancelled.');
    return;
end
exp.fpMatPath = fullfile(fpPath, fpName);

[ttlName, ttlPath] = uigetfile({'*.csv','TTLBox CSV (*.csv)'}, titleTTL);
if isequal(ttlName,0)
    exp.ttlCsvPath = '';
else
    exp.ttlCsvPath = fullfile(ttlPath, ttlName);
end

[usvName, usvPath] = uigetfile({'*.mat','DeepSqueak detection MAT (*.mat)'}, titleUSV);
if isequal(usvName,0)
    exp.usvMatPath = '';
else
    exp.usvMatPath = fullfile(usvPath, usvName);
end

end

function E = loadExperiment(fpMatPath, ttlCsvPath, usvMatPath, labelPrefix)

E = struct();
E.label = getLabelFromMat(fpMatPath);
E.sourceFP = fpMatPath;

% --- FP
[tFPraw, yFP] = loadCorrectedFP(fpMatPath);
if isempty(tFPraw) || isempty(yFP)
    error('%s: Corrected FP MAT did not yield usable vectors.', labelPrefix);
end

tFPraw = double(tFPraw(:));
yFP = double(yFP(:));

% If time looks like ms, convert to seconds
if numel(tFPraw) > 2
    dtMed = median(diff(tFPraw), 'omitnan');
else
    dtMed = NaN;
end
if ~isnan(dtMed) && dtMed > 1.5 && max(tFPraw) > 1000
    tFPraw = tFPraw / 1000;
end

% Force FP time to start at 0
E.tFP = tFPraw - tFPraw(1);
E.yFP = yFP;

% ---------------- Display-only scaling (DO NOT save scaled values) ----------------
% Project rule:
%   - Corrected FP saved in MAT stays as raw fraction (ΔF/F).
%   - Only plots use *100 to make values readable.
E.displayScale = 100;
E.yFP_plot = E.yFP * E.displayScale;

E.tEndFP = max(E.tFP);
if ~isfinite(E.tEndFP); E.tEndFP = 0; end

% Segment boundaries
E.b1 = E.tEndFP/3;
E.b2 = 2*E.tEndFP/3;

% --- TTL
E.ttl = struct('tStart',[],'wSec',[],'typeIdx',[]);
if ~isempty(ttlCsvPath)
    try
        [tStartShift, wSec] = loadTTLBoxLowPulses_Box15Style(ttlCsvPath);

        % IMPORTANT (your setup): the first TTL pulse is a start-marker,
        % not a behavioral event. Use it as reference, but do not plot it.
        if numel(tStartShift) >= 1
            tStartShift = tStartShift(2:end);
            wSec = wSec(2:end);
        end

        typeIdx = classifyTTLWidths(wSec, [20 40 60 80], 0.10);
        E.ttl.tStart = tStartShift;
        E.ttl.wSec   = wSec;
        E.ttl.typeIdx = typeIdx;
    catch ME
        warning('%s: TTL load failed: %s', labelPrefix, ME.message);
    end
end

% --- USV
E.usv = struct();
E.usv.tStart = [];
E.usv.label  = string.empty(0,1);
E.usv.cats   = string.empty(0,1);
E.usv.byCatTimes = {};
E.usv.byUnionCat = {};
E.usv.densityEdges = [];
E.usv.densityCenters = [];
E.usv.densityCounts = [];

if ~isempty(usvMatPath)
    try
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

        keep = isfinite(tS) & (tS >= 0);
        keep = keep & (lower(strtrim(lab)) ~= "noise");
        tS = tS(keep);
        lab = lab(keep);

        if isempty(lab)
            lab = repmat("USV", numel(tS), 1);
        end

        [labCanon, cats] = canonicalizeUSVLabels(lab);

        E.usv.tStart = tS;
        E.usv.label  = labCanon;
        E.usv.cats   = cats(:);

        E.usv.byCatTimes = cell(numel(E.usv.cats),1);
        for c = 1:numel(E.usv.cats)
            E.usv.byCatTimes{c} = E.usv.tStart(E.usv.label == E.usv.cats(c));
        end
    catch ME
        warning('%s: USV load failed: %s', labelPrefix, ME.message);
    end
end

% A common max time for density (FP vs TTL vs USV)
E.tEndAll = max([E.tEndFP, maxOrZero(E.ttl.tStart), maxOrZero(E.usv.tStart)]);
if ~isfinite(E.tEndAll); E.tEndAll = E.tEndFP; end

end

function v = maxOrZero(x)
if isempty(x)
    v = 0;
else
    v = max(x);
    if ~isfinite(v); v = 0; end
end
end

function label = getLabelFromMat(fpMatPath)
label = '';
try
    S = load(fpMatPath);
    if isfield(S,'sourcePhotometryCSV')
        try
            [~,b,~] = fileparts(S.sourcePhotometryCSV);
            label = b;
            return;
        catch
        end
    end
catch
end

[~,b,~] = fileparts(fpMatPath);
label = b;
end

%% ========================= Views =========================

function views = buildViews(E1, E2)
views = struct('title',{},'subtitle',{},'tA1',{},'tB1',{},'tA2',{},'tB2',{});

views(1).title = 'FULL';
views(1).subtitle = sprintf('FP1: [0..%.1fs] | FP2: [0..%.1fs]', E1.tEndFP, E2.tEndFP);
views(1).tA1 = 0; views(1).tB1 = E1.tEndFP;
views(1).tA2 = 0; views(1).tB2 = E2.tEndFP;

views(2).title = 'SEGMENT 1';
views(2).subtitle = 'First third of each recording';
views(2).tA1 = 0;    views(2).tB1 = E1.b1;
views(2).tA2 = 0;    views(2).tB2 = E2.b1;

views(3).title = 'SEGMENT 2';
views(3).subtitle = 'Second third of each recording';
views(3).tA1 = E1.b1; views(3).tB1 = E1.b2;
views(3).tA2 = E2.b1; views(3).tB2 = E2.b2;

views(4).title = 'SEGMENT 3';
views(4).subtitle = 'Final third of each recording';
views(4).tA1 = E1.b2; views(4).tB1 = E1.tEndFP;
views(4).tA2 = E2.b2; views(4).tB2 = E2.tEndFP;

end

%% ========================= USV categories & density =========================

function [catsUnion, catColors] = buildUnionCategories(usv1, usv2)
catsUnion = string.empty(0,1);

canonical = getCanonicalUSVList();
present = unique([usv1.cats(:); usv2.cats(:)], 'stable');
present = present(present~="");
present = present(present~="Noise");

for i=1:numel(canonical)
    if any(present == canonical(i))
        catsUnion(end+1,1) = canonical(i); %#ok<AGROW>
    end
end

for i=1:numel(present)
    if ~any(catsUnion == present(i))
        catsUnion(end+1,1) = present(i); %#ok<AGROW>
    end
end

if isempty(catsUnion)
    catColors = zeros(0,3);
else
    catColors = lines(numel(catsUnion));
end

end

function usv = mapUSVtoUnion(usv, catsUnion)
usv.byUnionCat = cell(numel(catsUnion),1);
if isempty(usv.tStart) || isempty(usv.label)
    for c=1:numel(catsUnion)
        usv.byUnionCat{c} = [];
    end
    return;
end

for c=1:numel(catsUnion)
    usv.byUnionCat{c} = usv.tStart(usv.label == catsUnion(c));
end
end

function usv = precomputeDensityCounts(usv, tEndAll, catsUnion, binSec)
if nargin < 4 || isempty(binSec) || ~isfinite(binSec) || binSec<=0
    binSec = 1.0;
end

tEndAll = double(tEndAll);
if ~isfinite(tEndAll) || tEndAll < 0
    tEndAll = 0;
end

edges = 0:binSec:(tEndAll + binSec);
if numel(edges) < 2
    edges = [0 binSec];
end
centers = edges(1:end-1) + binSec/2;

usv.densityEdges   = edges;
usv.densityCenters = centers(:);
usv.densityCounts  = zeros(numel(centers), numel(catsUnion));

for c=1:numel(catsUnion)
    tEv = [];
    if isfield(usv,'byUnionCat') && numel(usv.byUnionCat) >= c
        tEv = usv.byUnionCat{c};
    end
    if isempty(tEv)
        continue;
    end
    usv.densityCounts(:,c) = histcounts(tEv, edges).';
end

end

function [tC, dens] = densityFromCounts(countsByCat, edges, binSec, catSel)
% countsByCat: nBins x nCats
if isempty(edges)
    tC = 0.5; dens = 0; return;
end

tC = edges(1:end-1) + binSec/2;
tC = tC(:);

if isempty(countsByCat)
    dens = zeros(size(tC));
    return;
end

catSel = logical(catSel(:));
if numel(catSel) ~= size(countsByCat,2)
    catSel = true(size(countsByCat,2),1);
end

counts = sum(countsByCat(:,catSel), 2);
dens = smoothAndNormalizeDensity(counts, binSec);
end

function dens = smoothAndNormalizeDensity(counts, binSec)
counts = double(counts(:));
if isempty(counts)
    dens = 0;
    return;
end

% Smoothing
wBins = max(5, round(15/binSec));
if exist('smoothdata','file') == 2
    dens = smoothdata(counts, 'gaussian', wBins);
else
    dens = movmean(counts, wBins);
end

% Normalize (robust)
pos = dens(dens>0);
if isempty(pos)
    p = max(dens) + eps;
else
    p = prctile(pos, 99);
end
if ~isfinite(p) || p<=0
    p = max(dens) + eps;
end

dens = dens / (p + eps);
dens = min(dens, 1);
dens = max(dens, 0);
end

function hBand = plotDensityBand(ax, tC, dens)
% Draw a thin density band inside the axis (bottom 12% of y-range)
yl = ylim(ax);
yr = yl(2) - yl(1);
yBase = yl(1) + 0.02*yr;
yTop  = yl(1) + 0.14*yr;

dens = dens(:)';
tC = tC(:)';

y = yBase + (yTop - yBase) .* dens;
X = [tC fliplr(tC)];
Y = [yBase*ones(1,numel(tC)) fliplr(y)];

hBand = patch(ax, X, Y, [0.10 0.65 0.10], 'FaceAlpha',0.40, 'EdgeColor','none');
end

function updateDensityBandPatch(ax, hBand, tC, dens)
if ~isgraphics(ax) || ~isgraphics(hBand)
    return;
end

yl = ylim(ax);
yr = yl(2) - yl(1);
yBase = yl(1) + 0.02*yr;
yTop  = yl(1) + 0.14*yr;

dens = dens(:)';
tC = tC(:)';
y = yBase + (yTop - yBase) .* dens;

X = [tC fliplr(tC)];
Y = [yBase*ones(1,numel(tC)) fliplr(y)];

hBand.XData = X;
hBand.YData = Y;
end

function setHandlesVisible(h, tf)
if isempty(h), return; end
for k=1:numel(h)
    setHandleVisibleSafe(h(k), tf);
end
end

function setHandleVisibleSafe(h, tf)
if isempty(h) || ~isgraphics(h)
    return;
end
try
    % Set visibility in an explicit way (no ternary helper)
    if tf
        h.Visible = 'on';
    else
        h.Visible = 'off';
    end
catch
end
end


%% ========================= TTL helpers =========================

function typeIdx = classifyTTLWidths(wSec, codesMs, tolPct)
if nargin < 3 || isempty(tolPct)
    tolPct = 0.10;
end

if isempty(wSec)
    typeIdx = NaN(0,1);
    return;
end

wMs = double(wSec(:)) * 1000;
typeIdx = NaN(size(wMs));

for k = 1:numel(codesMs)
    target = codesMs(k);
    tol = tolPct * target;
    sel = abs(wMs - target) <= tol;
    typeIdx(sel) = k;
end

end

function [tStartShift, wSec, tRefRaw] = loadTTLBoxLowPulses_Box15Style(csvPath)
% Reads TTLBox CSV exported as alternating states, where LOW pulses are
% detected as False -> next True transitions (this matches your older
% FP_TTL_USV_* scripts).
%
% Returns:
%   tStartShift : pulse start times shifted so that FIRST PULSE START is t=0
%   wSec        : pulse widths in seconds
%   tRefRaw     : raw reference time used for shifting (first pulse start)

T = readtable(csvPath, 'Delimiter', ',', 'ReadVariableNames', false);

% Default outputs
tRefRaw = NaN;

% If the CSV contains multiple inputs/channels interleaved, restrict to the
% most common input label (e.g., 'Input0'). This prevents false width
% calculations across different inputs.
try
    if width(T) >= 1
        inCol = lower(strtrim(string(T{:,1})));
        if any(contains(inCol, "input"))
            [u,~,ic] = unique(inCol);
            cnt = accumarray(ic, 1);
            [~,imax] = max(cnt);
            T = T(ic == imax, :);
        end
    end
catch
end

% Find time and state columns robustly
% Time is usually column 4, but we search if needed
% State is usually column 2 or 3; we search for a text/logical column

% Time
if width(T) >= 4
    tRaw = T{:,4};
else
    tRaw = findFirstNumericColumn(T, 'time');
end

% State column: choose the column that actually contains True/False (or 1/0).
% Do NOT pick the first string column (often contains 'Input0').
stateCol = [];
bestHits = -inf;
bestDistinct = -inf;
N = height(T);
tfTokens = ["true","false","1","0"];
for c = 1:width(T)
    v = T{:,c};
    try
        s = string(v);
    catch
        continue;
    end
    s = lower(strtrim(s));
    hits = sum(ismember(s, tfTokens));
    if hits <= 0
        continue;
    end

    present = unique(s(ismember(s, tfTokens)));
    distinct = numel(present);

    % Prefer columns that contain BOTH states (distinct>=2), then maximize hits.
    if (distinct > bestDistinct) || (distinct == bestDistinct && hits > bestHits)
        bestDistinct = distinct;
        bestHits = hits;
        stateCol = c;
    end
end

if isempty(stateCol) || bestHits < max(5, round(0.20*N)) || bestDistinct < 2
    error('Could not find TTL state column containing True/False.');
end

stateVec = string(T{:,stateCol});

% Clean
stateVec = strtrim(stateVec);
tRaw = double(tRaw);
keep = isfinite(tRaw) & (strlength(stateVec) > 0);
tRaw = tRaw(keep);
stateVec = stateVec(keep);

if isempty(tRaw)
    tStartShift = [];
    wSec = [];
    tRefRaw = NaN;
    return;
end

% Detect transitions
isFalse = strcmpi(stateVec,'False') | strcmpi(stateVec,'0');
isTrue  = strcmpi(stateVec,'True')  | strcmpi(stateVec,'1');

tStart_raw = [];
tEnd_raw   = [];
for i = 1:numel(tRaw)-1
    if isFalse(i) && isTrue(i+1)
        w = tRaw(i+1) - tRaw(i);
        if isfinite(w) && w > 0
            tStart_raw(end+1,1) = tRaw(i);   %#ok<AGROW>
            tEnd_raw(end+1,1)   = tRaw(i+1); %#ok<AGROW>
        end
    end
end

if isempty(tStart_raw)
    tStartShift = [];
    wSec = [];
    return;
end

% Unit detection: if widths look like ms (~20/40/60/80), convert all to seconds
wRaw = tEnd_raw - tStart_raw;
if median(wRaw,'omitnan') > 1
    % Likely ms
    tStart_raw = tStart_raw / 1000;
    tEnd_raw   = tEnd_raw / 1000;
end

wSec = (tEnd_raw - tStart_raw);

% Shift so FIRST PULSE START becomes t=0 (same convention as your Excel script)
tRefRaw = tStart_raw(1);
tStartShift = tStart_raw - tRefRaw;

% Keep non-negative
keep2 = isfinite(tStartShift) & (tStartShift >= 0);
tStartShift = tStartShift(keep2);
wSec = wSec(keep2);

end

%% ========================= USV loading & labeling =========================

function [tStart, labels] = loadDeepSqueakStartTimesAndLabels(matPath)
% Loads start times and labels from a DeepSqueak detection MAT.
% Supports DeepSqueak where Calls is either a STRUCT array or a TABLE.
%
% Common patterns:
%   - Calls.Box(:,1) = start time (seconds)
%   - Labels in Calls.Type / Calls.Label / Calls.AcceptedType (varies)
%   - In many newer DS exports, Calls is a TABLE with variables Box, Type, etc.

S = load(matPath);

tStart = [];
labels = [];

if ~isfield(S,'Calls')
    return;
end

C = S.Calls;

% -------- TABLE format (newer DeepSqueak) --------
if istable(C)
    % Start times
    if any(strcmp(C.Properties.VariableNames,'Box'))
        box = C.Box;
        if isnumeric(box) && size(box,2) >= 1
            tStart = box(:,1);
        elseif iscell(box) && ~isempty(box)
            % Student style: extract first value in each Box cell using a simple loop
            n = numel(box);
            tStart = nan(n,1);

            for ii = 1:n
                b = box{ii};

                % Some DeepSqueak versions store Box as a nested cell (cell-in-cell)
                while iscell(b) && numel(b)==1
                    b = b{1};
                end

                if isnumeric(b) && ~isempty(b)
                    tStart(ii) = double(b(1));
                end
            end
        end
    end

    % Labels (priority order)
    cand = {'Type','Label','AcceptedType','CallType','Category','Class','Classification'};
    for k = 1:numel(cand)
        vn = cand{k};
        if any(strcmp(C.Properties.VariableNames, vn))
            labels = C.(vn);
            break;
        end
    end
    return;
end

% -------- STRUCT format (older DeepSqueak) --------
if isstruct(C)
    % Start times
    if isfield(C,'Box')
        box = C.Box;
        if isnumeric(box) && size(box,2) >= 1
            tStart = box(:,1);
        elseif iscell(box) && ~isempty(box)
            % Student style: extract first value in each Box cell using a simple loop
            n = numel(box);
            tStart = nan(n,1);

            for ii = 1:n
                b = box{ii};

                % Some DeepSqueak versions store Box as a nested cell (cell-in-cell)
                while iscell(b) && numel(b)==1
                    b = b{1};
                end

                if isnumeric(b) && ~isempty(b)
                    tStart(ii) = double(b(1));
                end
            end
        end
    end

    % Labels
    if isfield(C,'Type')
        labels = C.Type;
    elseif isfield(C,'Label')
        labels = C.Label;
    elseif isfield(C,'AcceptedType')
        labels = C.AcceptedType;
    elseif isfield(C,'CallType')
        labels = C.CallType;
    elseif isfield(C,'Category')
        labels = C.Category;
    end
end

end

function [labelsOut, catsOrdered] = canonicalizeUSVLabels(labelsIn)
labelsIn = string(labelsIn(:));

labelsOut = strings(size(labelsIn));
for i=1:numel(labelsIn)
    labelsOut(i) = normalizeUSVLabel(labelsIn(i));
end

% Replace empties with USV
labelsOut(labelsOut=="") = "USV";

catsOrdered = unique(labelsOut,'stable');

% Reorder by canonical list
canonical = getCanonicalUSVList();
ordered = string.empty(0,1);
for i=1:numel(canonical)
    if any(catsOrdered == canonical(i))
        ordered(end+1,1) = canonical(i); %#ok<AGROW>
    end
end
for i=1:numel(catsOrdered)
    if ~any(ordered == catsOrdered(i))
        ordered(end+1,1) = catsOrdered(i); %#ok<AGROW>
    end
end
catsOrdered = ordered;
end

function s = normalizeUSVLabel(s)
% Make labels consistent across DeepSqueak variants / typos
s = string(s);
s = strtrim(s);
if s==""; return; end

% Normalize separators / case
sLow = lower(s);

% Common DS categories (your set)
% Student style mapping: use two lists (keys + values) and a loop.
% (We keep the same mapping choices as before; just written more explicitly.)
keys = { ...
    'usv', ...
    'complex', ...
    'step up', 'stepup', ...
    'unclear', ...
    'short', ...
    'step down', 'stepdown', ...
    'inverted u', 'invertedu', ...
    'trill with jumps', 'trillwithjumps', ...
    'flat', ...
    'upward ramp', 'upwardramp', ...
    'flat trill combination', 'flattrillcombination', ...
    'trill', ...
    'multi step', 'multistep', ...
    'split', ...
    'composite', ...
    'downward ramp', 'downwardramp', ...
    '22-khz', '22khz', '22 khz', ...
    'miscellaneuous', 'miscellaneous', 'misc', ...
    'multi-step', ...
    'flat-trill', 'flat trill', ...
    'flat-trill combination', ...
    'noise' ...
    };

values = { ...
    'USV', ...
    'Complex', ...
    'Step Up', 'Step Up', ...
    'Unclear', ...
    'Short', ...
    'Step Down', 'Step Down', ...
    'Inverted U', 'Inverted U', ...
    'Trill with jumps', 'Trill with jumps', ...
    'Flat', ...
    'Upward ramp', 'Upward ramp', ...
    'Flat trill combination', 'Flat trill combination', ...
    'Trill', ...
    'Multi Step', 'Multi Step', ...
    'Split', ...
    'Composite', ...
    'Downward ramp', 'Downward ramp', ...
    '22-KHz', '22-KHz', '22-KHz', ...
    'Miscellaneous', 'Miscellaneous', 'Miscellaneous', ...
    'Multi-Step', ...
    'Flat-trill', 'Flat-trill', ...
    'Flat trill combination', ...
    'Noise' ...
    };

found = false;
for kk = 1:numel(keys)
    if strcmp(sLow, keys{kk})
        s = string(values{kk});
        found = true;
        break;
    end
end

if ~found
    % Title-case fallback
    s = regexprep(s, '_', ' ');
    s = regexprep(s, '\s+', ' ');
    % Capitalize first letter of each word
    parts = split(lower(s));
    parts(parts=="") = [];
    for k=1:numel(parts)
        w = char(parts(k));
        parts(k) = string([upper(w(1)) w(2:end)]);
    end
    if isempty(parts)
        s = "";
    else
        s = join(parts, ' ');
    end
end
end

function canonical = getCanonicalUSVList()
canonical = [ ...
    "USV"; ...
    "Complex"; ...
    "Upward ramp"; ...
    "Downward ramp"; ...
    "Flat"; ...
    "Short"; ...
    "Split"; ...
    "Step Up"; ...
    "Step Down"; ...
    "Multi-Step"; ...
    "Trill"; ...
    "Flat-trill"; ...
    "Trill with jumps"; ...
    "Inverted U"; ...
    "Composite"; ...
    "22-KHz"; ...
    "Unclear"; ...
    "Miscellaneous"; ...
    "Noise" ...
];
end

%% ========================= Corrected FP loading =========================

function [tFP, yFP] = loadCorrectedFP(matPath)
% Supports common saved formats from your correction pipeline.
S = load(matPath);

% 1) correctedSignalTable with Time_s and CorrectedSignal
if isfield(S,'correctedSignalTable') && istable(S.correctedSignalTable)
    T = S.correctedSignalTable;
    if all(ismember({'Time_s','CorrectedSignal'}, T.Properties.VariableNames))
        tFP = T.Time_s;
        yFP = T.CorrectedSignal;
        return;
    end
end

% 2) tablediffRelative with SystemTimestamp/Time_s + CorrectedSignal
if isfield(S,'tablediffRelative') && istable(S.tablediffRelative)
    T = S.tablediffRelative;
    % Try common time columns
    if any(strcmpi(T.Properties.VariableNames,'Time_s'))
        tFP = T{:, find(strcmpi(T.Properties.VariableNames,'Time_s'),1,'first')};
    elseif any(strcmpi(T.Properties.VariableNames,'SystemTimestamp'))
        tFP = T{:, find(strcmpi(T.Properties.VariableNames,'SystemTimestamp'),1,'first')};
    else
        tFP = findFirstNumericColumn(T, 'time');
    end

    if any(strcmpi(T.Properties.VariableNames,'CorrectedSignal'))
        yFP = T{:, find(strcmpi(T.Properties.VariableNames,'CorrectedSignal'),1,'first')};
    else
        yFP = findFirstNumericColumn(T, 'signal');
    end

    return;
end

% 3) Any two numeric vectors in workspace
% Attempt: find the longest numeric vector as signal and another monotonic vector as time
nums = struct();
fn = fieldnames(S);
for k=1:numel(fn)
    v = S.(fn{k});
    if isnumeric(v) && isvector(v) && numel(v) > 10
        nums.(fn{k}) = v(:);
    end
end

% Prefer explicit names
candTime = [];
candSig  = [];
if isfield(nums,'tFP'); candTime = nums.tFP; end
if isfield(nums,'Time_s'); candTime = nums.Time_s; end
if isfield(nums,'CorrectedSignal'); candSig = nums.CorrectedSignal; end
if isfield(nums,'yFP'); candSig = nums.yFP; end

if ~isempty(candTime) && ~isempty(candSig)
    tFP = candTime; yFP = candSig; return;
end

% Fallback: pick two longest vectors
names = fieldnames(nums);
if numel(names) < 2
    tFP = []; yFP = []; return;
end
lens = zeros(numel(names),1);
for k=1:numel(names)
    lens(k) = numel(nums.(names{k}));
end
[~,ord] = sort(lens,'descend');
A = nums.(names{ord(1)});
B = nums.(names{ord(2)});

% Choose time as the more monotonic one
isMonoA = all(diff(A(~isnan(A))) >= 0);
isMonoB = all(diff(B(~isnan(B))) >= 0);

if isMonoA && ~isMonoB
    tFP = A; yFP = B;
elseif isMonoB && ~isMonoA
    tFP = B; yFP = A;
else
    % Default: assume A is time, B is signal
    tFP = A; yFP = B;
end

end

function col = findFirstNumericColumn(T, which)
% Returns first numeric column as a vector.
% which: hint string (unused; kept for compatibility)
col = [];
for c=1:width(T)
    v = T{:,c};
    if isnumeric(v)
        col = v;
        return;
    end
end
end