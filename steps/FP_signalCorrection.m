function out = FP_signalCorrection(photoCsvPath, varargin)
% FP_signalCorrection (PASS 2: extra-declustered + heavily commented)
% -------------------------------------------------------------------------
% PURPOSE
%   Read a photometry CSV (fiber photometry), split LED channels, and compute
%   a corrected signal. This function is used by your pipeline runner
%   FP_signalCorrection_run.m, and also can be used standalone.
%
% KEY IDEA (same as your original)
%   - LedState == 2  => "signal" channel (e.g., 465 nm)
%   - LedState == 1  => "control" channel (e.g., 405 nm)
%   - We create an "artificial control" when signal/control diverge a lot.
%   - Corrected ΔF/F is computed as: (signal - correctedControl) / correctedControl
%   - Then we zero-center (subtract the mean)
%
% IMPORTANT
%   - This file MUST keep the same behavior/output fields as before.
%   - This is a readability + comments refactor only.
%
% INPUTS
%   photoCsvPath : photometry CSV file path (char/string). If empty => dialog.
%   varargin     : Name-Value options (see below)
%
% NAME-VALUE OPTIONS (same as before)
%   'MakePlots'          : true/false (default: true if interactive, else false)
%   'SaveMat'            : true/false (default: true)
%   'OutDir'             : output folder (default: folder of the CSV)
%   'Verbose'            : true/false (default: true)
%   'FilterEnable'       : true/false (default: true)
%   'FilterFrac'         : fraction of signal length for movmean filter window
%   'MeanFrac'           : fraction of signal length for moving mean window
%   'StdFrac'            : fraction of signal length for moving std window
%   'ControlSmoothFrac'  : fraction for smoothing corrected control (movmean)
%
% OUTPUT (struct) fields (same as before)
%   out.sourcePhotometryCSV
%   out.correctedSignalTable   (table: Time_s, CorrectedSignal)
%   out.tablediffRelative      (table: [timeSignal, CorrectedSignal] no var names)
%   out.outMatFile
%   out.figures
% -------------------------------------------------------------------------


%% =====================================================================
% 0) HANDLE MISSING INPUT (allow FP_signalCorrection() with dialog)
% =====================================================================

% If user did not provide the first input argument, set it to empty.
if nargin < 1
    photoCsvPath = '';
end

% "Interactive mode" means we ask user to pick the file.
interactiveMode = isempty(photoCsvPath);

% Default plot behavior:
% - In interactive mode, plots are helpful, so default to true.
% - In non-interactive mode (app pipeline), plots are usually not wanted.
defaultMakePlots = interactiveMode;


%% =====================================================================
% 1) DEFAULT OPTIONS (student-style explicit defaults)
% =====================================================================
opts = struct();

% Should we show diagnostic figures?
opts.MakePlots = defaultMakePlots;

% Should we save the corrected signal as a MAT file?
opts.SaveMat = true;

% Where to save (if SaveMat = true)
opts.OutDir = '';

% Print messages and warnings?
opts.Verbose = true;

% Filter the signal channel with movmean first?
opts.FilterEnable = true;

% Window-size fractions (these are converted to sample counts later)
opts.FilterFrac = 0.001;        % small smoothing window for the signal
opts.MeanFrac   = 0.01;         % window for moving mean (artificial control base)
opts.StdFrac    = 0.01;         % window for moving std (boundaries)
opts.ControlSmoothFrac = 0.005; % smoothing window for corrected control


%% =====================================================================
% 2) PARSE NAME-VALUE OPTIONS (manual, beginner-style)
% =====================================================================

% If user passed any options, they must come in pairs:
%   'Name1', Value1, 'Name2', Value2, ...
if ~isempty(varargin)

    % Must be an even number of items.
    if mod(numel(varargin), 2) ~= 0
        error('FP_signalCorrection:BadArgs', ...
            'Name-Value inputs must come in pairs.');
    end

    % Walk through pairs: (1,2), (3,4), ...
    k = 1;
    while k <= numel(varargin)

        % Read one name-value pair
        nameIn  = varargin{k};
        valueIn = varargin{k+1};

        % Option names must be text
        if ~(ischar(nameIn) || isstring(nameIn))
            error('FP_signalCorrection:BadArgs', ...
                'Option name at position %d must be text.', k);
        end

        % Normalize option name to lower-case char (safe for older MATLAB)
        key = lower(char(string(nameIn)));

        % Apply each supported option
        if strcmp(key, 'makeplots')
            % Convert to logical, and require scalar
            tmp = logical(valueIn);
            if ~isscalar(tmp)
                error('FP_signalCorrection:BadOption', 'MakePlots must be a scalar true/false.');
            end
            opts.MakePlots = tmp;

        elseif strcmp(key, 'savemat')
            tmp = logical(valueIn);
            if ~isscalar(tmp)
                error('FP_signalCorrection:BadOption', 'SaveMat must be a scalar true/false.');
            end
            opts.SaveMat = tmp;

        elseif strcmp(key, 'outdir')
            opts.OutDir = valueIn;

        elseif strcmp(key, 'verbose')
            tmp = logical(valueIn);
            if ~isscalar(tmp)
                error('FP_signalCorrection:BadOption', 'Verbose must be a scalar true/false.');
            end
            opts.Verbose = tmp;

        elseif strcmp(key, 'filterenable')
            tmp = logical(valueIn);
            if ~isscalar(tmp)
                error('FP_signalCorrection:BadOption', 'FilterEnable must be a scalar true/false.');
            end
            opts.FilterEnable = tmp;

        elseif strcmp(key, 'filterfrac')
            opts.FilterFrac = double(valueIn);

        elseif strcmp(key, 'meanfrac')
            opts.MeanFrac = double(valueIn);

        elseif strcmp(key, 'stdfrac')
            opts.StdFrac = double(valueIn);

        elseif strcmp(key, 'controlsmoothfrac')
            opts.ControlSmoothFrac = double(valueIn);

        else
            error('FP_signalCorrection:UnknownOption', ...
                'Unknown option: %s', key);
        end

        % Move to the next pair
        k = k + 2;
    end
end


%% =====================================================================
% 2b) VALIDATE NUMERIC OPTIONS (avoid silent bugs)
% =====================================================================

% Each *_Frac value must be a positive scalar number.
if ~(isnumeric(opts.FilterFrac) && isscalar(opts.FilterFrac) && opts.FilterFrac > 0)
    error('FP_signalCorrection:BadOption', 'FilterFrac must be a scalar > 0.');
end

if ~(isnumeric(opts.MeanFrac) && isscalar(opts.MeanFrac) && opts.MeanFrac > 0)
    error('FP_signalCorrection:BadOption', 'MeanFrac must be a scalar > 0.');
end

if ~(isnumeric(opts.StdFrac) && isscalar(opts.StdFrac) && opts.StdFrac > 0)
    error('FP_signalCorrection:BadOption', 'StdFrac must be a scalar > 0.');
end

if ~(isnumeric(opts.ControlSmoothFrac) && isscalar(opts.ControlSmoothFrac) && opts.ControlSmoothFrac > 0)
    error('FP_signalCorrection:BadOption', 'ControlSmoothFrac must be a scalar > 0.');
end


%% =====================================================================
% 3) CHOOSE FILE (if interactive mode)
% =====================================================================

if interactiveMode

    % Ask user to choose a photometry CSV
    [fn, fp] = uigetfile({'*.csv','Photometry CSV (*.csv)'}, ...
        'Select photometry CSV');

    % If user cancels, uigetfile returns 0
    if isequal(fn, 0)
        error('FP_signalCorrection:NoFileSelected', ...
            'No photometry CSV selected.');
    end

    % Build full path
    photoCsvPath = fullfile(fp, fn);

else
    % Ensure path is a plain char string
    photoCsvPath = char(string(photoCsvPath));
end


%% =====================================================================
% 4) VALIDATE FILE + OUTPUT FOLDER
% =====================================================================

% The photometry CSV must exist.
if ~isfile(photoCsvPath)
    error('FP_signalCorrection:FileNotFound', ...
        'Photometry CSV not found: %s', photoCsvPath);
end

% Decide output folder:
% - If user did not provide OutDir, use the CSV folder.
% - Else, use provided OutDir.
if isempty(opts.OutDir)
    outDir = fileparts(photoCsvPath);
else
    outDir = char(string(opts.OutDir));
end

% Create the folder if it does not exist
if ~exist(outDir, 'dir')
    mkdir(outDir);
end


%% =====================================================================
% 5) READ PHOTOMETRY CSV
% =====================================================================

% Read CSV into a table.
% MATLAB automatically reads headers into variable names.
T = readtable(photoCsvPath);

% Required columns (same as before)
requiredCols = {'SystemTimestamp', 'LedState', 'G0'};

% Find missing columns
missingCols = requiredCols(~ismember(requiredCols, T.Properties.VariableNames));

% Stop if required columns are missing
if ~isempty(missingCols)
    error('FP_signalCorrection:MissingColumns', ...
        'Missing required columns: %s', strjoin(missingCols, ', '));
end

% Normalize time to start at zero (same behavior as original)
T.SystemTimestamp = T.SystemTimestamp - T.SystemTimestamp(1);

% We need at least a few rows to split LED states.
if height(T) < 3
    error('FP_signalCorrection:TooShort', ...
        'Photometry table too short.');
end

% Remove first row (original behavior)
% This often removes a startup artifact line.
T = T(2:end, :);


%% =====================================================================
% 6) TRIM UNTIL LedState EDGES DIFFER (original behavior)
% =====================================================================

% The original code trimmed from the beginning while the FIRST and LAST
% LedState values are the same. This helps ensure a clean alternation.
trimGuard = 0;

while height(T) > 2 && T.LedState(1) == T.LedState(end)

    % Remove one row from the start
    T = T(2:end, :);

    % Safety guard against infinite loops (should never happen realistically)
    trimGuard = trimGuard + 1;
    if trimGuard > 1e6
        error('FP_signalCorrection:TrimLoop', ...
            'Safety stop: trimming loop did not converge.');
    end
end


%% =====================================================================
% 7) SPLIT INTO CONTROL AND SIGNAL CHANNELS
% =====================================================================

% Control channel = LedState 1
Tcontrol = T(T.LedState == 1, :);

% Signal channel = LedState 2
Tsignal  = T(T.LedState == 2, :);

% If one channel is missing, we cannot compute ΔF/F
if isempty(Tcontrol) || isempty(Tsignal)
    error('FP_signalCorrection:MissingChannels', ...
        'Could not split LedState=1 vs LedState=2.');
end

% Extract times for each stream
timeControl = Tcontrol.SystemTimestamp;   % timestamps for control samples
timeSignal  = Tsignal.SystemTimestamp;    % timestamps for signal samples

% Extract control raw values (kept for plots)
controlRaw = Tcontrol.G0;


%% =====================================================================
% 8) WINDOW SIZES FROM FRACTIONS (convert frac -> samples)
% =====================================================================

% Number of samples in the signal stream
nSig = height(Tsignal);

% Convert fraction -> number of samples (at least 1)
wFilter = max(1, round(opts.FilterFrac * nSig));  % smoothing for signal
wMean   = max(1, round(opts.MeanFrac   * nSig));  % moving mean window
wStd    = max(1, round(opts.StdFrac    * nSig));  % moving std window


%% =====================================================================
% 9) PREPARE SIGNAL AND BOUNDARIES (moving mean ± moving std)
% =====================================================================

% Start from raw signal values
signalRaw = Tsignal.G0;

% Optionally smooth the signal first (same as before)
if opts.FilterEnable
    % movmean = moving average filter
    signal = movmean(signalRaw, wFilter);
else
    signal = signalRaw;
end

% Moving mean and moving standard deviation on the (filtered) signal
mSignal    = movmean(signal, wMean);
mstdSignal = movstd(signal,  wStd);

% Boundaries used for control correction logic
upperBoundary = mSignal + mstdSignal;
lowerBoundary = mSignal - mstdSignal;


%% =====================================================================
% 10) MATCH LENGTHS AND TRUNCATE (signal and control can differ by 1)
% =====================================================================

% Control vector used for correction logic (raw control)
control = controlRaw;

% Use the minimum length so all vectors align 1-to-1
minN = min(numel(signal), numel(control));

% If lengths differ, inform user (same warning behavior)
if numel(signal) ~= numel(control) && opts.Verbose
    warning('FP_signalCorrection:LengthMismatch', ...
        'Signal and control length differ; truncating.');
end

% Truncate all relevant vectors to the same length
signal        = signal(1:minN);
control       = control(1:minN);
timeSignal    = timeSignal(1:minN);
timeControl   = timeControl(1:minN);

mSignal       = mSignal(1:minN);
mstdSignal    = mstdSignal(1:minN);
upperBoundary = upperBoundary(1:minN);
lowerBoundary = lowerBoundary(1:minN); %#ok<NASGU>  % kept for clarity (even if unused later)


%% =====================================================================
% 11) BUILD CORRECTED CONTROL (explicit loop, same logic as before)
% =====================================================================

% Preallocate corrected control vector
newControl = zeros(size(control));

% We decide, at each sample i:
%   If control(i) is very different from signal(i), replace it with mSignal(i),
%   otherwise keep the original control(i).
for i = 1:minN

    % Same "threshold" expression you had before (kept identical)
    thresholdVal = abs(mSignal(i) - (mSignal(i) - 0.1 * mstdSignal(i)));

    % If difference is big -> use artificial control (moving mean)
    if abs(control(i) - signal(i)) >= thresholdVal
        newControl(i) = mSignal(i);
    else
        % Otherwise keep real control
        newControl(i) = control(i);
    end
end

% Smooth corrected control to reduce jitter
wCtrl = max(1, round(opts.ControlSmoothFrac * minN));
newControl = movmean(newControl(:), wCtrl);


%% =====================================================================
% 12) COMPUTE CORRECTED SIGNAL (ΔF/F) + ZERO-CENTER
% =====================================================================

% Difference between signal and corrected control
diffSignalControl = signal - newControl;

% Relative difference: (signal - control) / control  (ΔF/F-like)
diffRelative = diffSignalControl ./ newControl;

% Zero-center the corrected trace (same as original behavior)
diffRelativeZeroCentered = diffRelative - mean(diffRelative);


%% =====================================================================
% 13) OUTPUT TABLES (same shape/fields as before)
% =====================================================================

% Table without custom variable names (kept for backward compatibility)
tablediffRelative = array2table([timeSignal(:) diffRelativeZeroCentered(:)]);

% Clean table with variable names (this is what you typically use)
correctedSignalTable = table( ...
    timeSignal(:), ...
    diffRelativeZeroCentered(:), ...
    'VariableNames', {'Time_s', 'CorrectedSignal'});


%% =====================================================================
% 14) SAVE MAT FILE (optional)
% =====================================================================

% Output MAT name is based on CSV filename
[~, baseName, ~] = fileparts(photoCsvPath);
outMatName = sprintf('%s_CorrectedSignal.mat', baseName);
outMatFile = fullfile(outDir, outMatName);

% Keep this variable name in the MAT file (your pipeline expects it)
sourcePhotometryCSV = photoCsvPath; %#ok<NASGU>

if opts.SaveMat

    % Save exactly the same variables as before
    save(outMatFile, 'correctedSignalTable', 'tablediffRelative', 'sourcePhotometryCSV');

    if opts.Verbose
        fprintf('Saved corrected signal to: %s\n', outMatFile);
    end

else
    % If not saving, return empty outMatFile string
    outMatFile = '';
end


%% =====================================================================
% 15) FIGURES (optional diagnostic plots)
% =====================================================================
figs = gobjects(0);  % default: no figures

if opts.MakePlots

    % Color used for the boundary shading in plot #2
    shadeColor = [133/250 193/250 233/250];

    % Preallocate figure handle array (same number of figures as before)
    figs = gobjects(6, 1);

    % -----------------------------------------------------------------
    % Figure 1: Raw results (signal + real control)
    % -----------------------------------------------------------------
    figs(1) = figure('Name', 'Raw results', 'NumberTitle', 'off');

    % Plot signal
    plot(timeSignal, signal, 'DisplayName', 'Signal');
    hold on;

    % Plot control (truncated to minN so x/y match)
    plot(timeControl, controlRaw(1:minN), 'DisplayName', 'Real Control');

    xlabel('Time [s]');
    legend('Location', 'northeast');
    title('Raw results');

    % -----------------------------------------------------------------
    % Figure 2: Signal boundaries (moving mean ± moving std)
    % -----------------------------------------------------------------
    figs(2) = figure('Name', 'Signal boundaries', 'NumberTitle', 'off');

    % Plot signal again
    plot(timeSignal, signal, 'DisplayName', 'Signal');
    hold on;

    % Shaded area between upperBoundary and lowerBoundary
    patch( ...
        [timeSignal(:); flipud(timeSignal(:))], ...      % x polygon
        [upperBoundary(:); flipud(lowerBoundary(:))], ... % y polygon
        shadeColor, ...
        'FaceAlpha', 0.5, ...
        'EdgeColor', 'none', ...
        'HandleVisibility', 'off');

    % Plot the moving mean (artificial control baseline)
    plot(timeSignal, mSignal, 'DisplayName', 'Artificial Control (moving mean)');

    legend('Location', 'northeast');
    title('Signal boundaries');

    % -----------------------------------------------------------------
    % Figure 3: Corrected control (signal + corrected control)
    % -----------------------------------------------------------------
    figs(3) = figure('Name', 'Corrected control', 'NumberTitle', 'off');

    plot(timeSignal, signal, 'DisplayName', 'Signal');
    hold on;

    plot(timeControl, newControl, 'DisplayName', 'Corrected Control');

    xlabel('Time [s]');
    legend('Location', 'northeast');
    title('Corrected control');

    % -----------------------------------------------------------------
    % Figure 4: Signal - control
    % -----------------------------------------------------------------
    figs(4) = figure('Name', 'Signal - control', 'NumberTitle', 'off');

    plot(timeSignal, diffSignalControl, 'DisplayName', 'Signal - Control');
    hold on;

    xlabel('Time [s]');
    legend('Location', 'northeast');
    title('Signal - Control');

    % -----------------------------------------------------------------
    % Figure 5: (Signal-control)/control (non-zero-centered)
    % -----------------------------------------------------------------
    figs(5) = figure('Name', '(Signal-control)/control', 'NumberTitle', 'off');

    plot(timeSignal, diffRelative, 'DisplayName', '(Signal-control)/control');
    hold on;

    grid on;

    % Plot mean line as reference
    plot(timeSignal, mean(diffRelative) * ones(size(diffRelative)), ...
        'HandleVisibility', 'off');

    xlabel('Time [s]');
    legend('Location', 'northeast');
    title('(Signal-control)/control');

    % -----------------------------------------------------------------
    % Figure 6: Zero-centered trace
    % -----------------------------------------------------------------
    figs(6) = figure('Name', 'Zero-centered', 'NumberTitle', 'off');

    plot(timeSignal, diffRelativeZeroCentered);
    hold on;

    grid on;

    % Plot mean line (should be near 0)
    plot(timeSignal, mean(diffRelativeZeroCentered) * ones(size(diffRelativeZeroCentered)), ...
        'HandleVisibility', 'off');

    xlabel('Time [s]');
    title('Zero-centered (Signal-control)/control');

end


%% =====================================================================
% 16) PACK OUTPUT STRUCT (same field names as before)
% =====================================================================
out = struct();

out.sourcePhotometryCSV  = photoCsvPath;          % input CSV path
out.correctedSignalTable = correctedSignalTable;  % clean table (Time_s, CorrectedSignal)
out.tablediffRelative    = tablediffRelative;     % compatibility table
out.outMatFile           = outMatFile;            % saved MAT path (or empty)
out.figures              = figs;                  % figure handles (or empty)

end
