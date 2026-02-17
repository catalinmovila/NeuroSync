function outMatFile = FP_signalCorrection_run(photoCsv, varargin)
% FP_signalCorrection_run (PASS 2: extra-declustered + very heavily commented)
% -------------------------------------------------------------------------
% WHAT THIS WRAPPER DOES
%   This is the "runner" used by the app button.
%   It takes ONE photometry CSV and produces ONE MAT file:
%
%       <baseName>_CorrectedSignal.mat
%
% That MAT contains these variables (kept for backward compatibility):
%   - correctedSignalTable : table with columns (Time_s, CorrectedSignal)
%   - tablediffRelative    : legacy 2-column table (time, corrected) with Var1/Var2 names
%   - sourcePhotometryCSV  : char path to the input CSV
%
% DESIGN RULES FOR THIS PASS
%   - Same behavior and deliverables as your previous version.
%   - More explicit "student style" code:
%       * step-by-step variables
%       * simple loops and explicit if/else blocks
%       * extra comments (including line-level where it helps)
%
% USAGE
%   outMatFile = FP_signalCorrection_run(photoCsv)
%   outMatFile = FP_signalCorrection_run(photoCsv, 'ShowPlots', true, 'OutDir', 'C:\...\Output files')
%
% NAME-VALUE OPTIONS
%   'ShowPlots' : true/false (default = true)
%   'OutDir'    : output folder for MAT (default = folder of photoCsv)
% -------------------------------------------------------------------------


%% =====================================================================
% 1) DEFAULTS + INPUT CLEANUP
% =====================================================================

% Default: show plots (same as your current runner)
showPlots = true;

% Default: output directory (empty means: use CSV folder)
outDir = "";

% If user did not pass photoCsv, treat it as empty => open file picker
if nargin < 1
    photoCsv = "";
end

% Convert to string for easier checks
photoCsv = string(photoCsv);


%% =====================================================================
% 2) PARSE NAME-VALUE OPTIONS (manual, beginner-style)
% =====================================================================
% We expect pairs like: 'ShowPlots', true, 'OutDir', 'C:\...'
if ~isempty(varargin)

    % If we have an odd number of inputs, it is invalid
    if mod(numel(varargin), 2) ~= 0
        error('FP_signalCorrection_run:BadInputs', ...
            'Name-value inputs must come in pairs, e.g. ''ShowPlots'',true.');
    end

    % Walk through pairs (1,2), (3,4), ...
    for k = 1:2:numel(varargin)

        % Read one option name + value
        optName  = string(varargin{k});
        optValue = varargin{k+1};

        % Compare option name ignoring case
        if strcmpi(optName, "ShowPlots")

            % Validate value type
            if islogical(optValue) && isscalar(optValue)
                showPlots = optValue;
            else
                error('FP_signalCorrection_run:BadShowPlots', ...
                    '''ShowPlots'' must be a scalar logical (true/false).');
            end

        elseif strcmpi(optName, "OutDir")

            % Accept char or string
            if ischar(optValue) || isstring(optValue)
                outDir = string(optValue);
            else
                error('FP_signalCorrection_run:BadOutDir', ...
                    '''OutDir'' must be a string/char path.');
            end

        else
            % Anything else is unknown
            error('FP_signalCorrection_run:UnknownOption', ...
                'Unknown option: %s', optName);
        end
    end
end


%% =====================================================================
% 3) PICK THE PHOTOMETRY CSV IF NEEDED
% =====================================================================
% If photoCsv is empty OR doesn't exist, ask user to pick a file.
% This keeps the behavior you had in the previous version.

if strlength(photoCsv) == 0 || ~isfile(photoCsv)

    % Ask user to select the photometry CSV
    [fileName, filePath] = uigetfile({ ...
        '*.csv', 'Photometry CSV (*.csv)'; ...
        '*.*',   'All files (*.*)'}, ...
        'Select photometry CSV');

    % If cancelled, uigetfile returns 0
    if isequal(fileName, 0)
        error('FP_signalCorrection_run:NoFileSelected', ...
            'No photometry CSV selected.');
    end

    % Build the full path
    photoCsv = string(fullfile(filePath, fileName));
end


%% =====================================================================
% 4) READ + VALIDATE PHOTOMETRY CSV TABLE
% =====================================================================

% Read the file into a table
T = readtable(photoCsv);

% Required columns for this algorithm (same as before)
requiredCols = ["SystemTimestamp", "LedState", "G0"];

% Check each required column explicitly
for i = 1:numel(requiredCols)

    colName = requiredCols(i);

    % If missing, stop early with a clear error
    if ~ismember(colName, T.Properties.VariableNames)
        error('FP_signalCorrection_run:MissingColumn', ...
            'Photometry CSV is missing required column "%s".', colName);
    end
end

% Make time start at 0 seconds (same as before)
T.SystemTimestamp = T.SystemTimestamp - T.SystemTimestamp(1);

% Guard: we need enough rows to split LEDs
if height(T) < 3
    error('FP_signalCorrection_run:TooShort', ...
        'Photometry CSV is too short.');
end

% Drop the first row (startup artifact; same as before)
T = T(2:end, :);


%% =====================================================================
% 5) ALIGN LED CYCLES (TRIM UNTIL FIRST AND LAST LedState DIFFER)
% =====================================================================
% This step matches your previous behavior.
% The reason: if the file begins in the middle of a LED cycle,
% the alternating pattern might be offset, and pairing becomes messy.

while height(T) > 2 && T.LedState(1) == T.LedState(end)
    T = T(2:end, :);
end


%% =====================================================================
% 6) SPLIT CONTROL/SIGNAL BY LED STATE
% =====================================================================
% Control channel (often 405 nm) is LedState==1
% Signal channel (often 465 nm)  is LedState==2

Tcontrol = T(T.LedState == 1, :);
Tsignal  = T(T.LedState == 2, :);

% Extract time vectors for each channel
timeControl = Tcontrol.SystemTimestamp;
timeSignal  = Tsignal.SystemTimestamp;

% Extract raw vectors (G0)
controlRaw = Tcontrol.G0;
signalRaw  = Tsignal.G0;

% Safety: must have both channels
if isempty(controlRaw) || isempty(signalRaw)
    error('FP_signalCorrection_run:MissingChannels', ...
        'Could not split into LedState==1 and LedState==2 channels.');
end


%% =====================================================================
% 7) SMOOTH SIGNAL + BUILD ARTIFICIAL CONTROL ENVELOPE
% =====================================================================

% Start with the signal vector (will be filtered)
signal = signalRaw;

% The original runner used moving mean with window = 0.1% of samples
useMovingMean = true;

if useMovingMean
    winSignal = 0.001 * size(Tsignal, 1);  % NOTE: keep identical expression
    signal = movmean(signal, winSignal);   % smooth signal
end

% Artificial control envelope:
%   moving mean ± moving std using a 1% window
winEnv = 0.01 * size(signal, 1);   % NOTE: keep identical expression
mSignal    = movmean(signal, winEnv);
mstdSignal = movstd(signal,  winEnv);

upperBoundary = mSignal + mstdSignal;
lowerBoundary = mSignal - mstdSignal;


%% =====================================================================
% 8) OPTIONAL DIAGNOSTIC PLOTS (same figures, more explicit)
% =====================================================================
if showPlots

    % 8.1 Raw results
    figure('Name', 'FP correction - Raw results', 'NumberTitle', 'off');
    plot(timeSignal, signal, 'DisplayName', 'Signal'); hold on;
    plot(timeControl, controlRaw, 'DisplayName', 'Real Control');
    xlabel('Time [s]');
    legend('Location', 'northeast');
    title('Raw results');

    % 8.2 Artificial control envelope
    figure('Name', 'FP correction - Artificial control', 'NumberTitle', 'off');
    plot(timeSignal, signal, 'DisplayName', 'Signal'); hold on;

    shadeColor = [133/250 193/250 233/250];   % same color as your previous version

    % Draw shaded band between upper and lower boundaries
    patch([timeSignal; flip(timeSignal)], ...
          [upperBoundary; flip(lowerBoundary)], ...
          shadeColor, ...
          'FaceAlpha', 0.5, ...
          'EdgeColor', 'none', ...
          'HandleVisibility', 'off');

    plot(timeSignal, mSignal, 'DisplayName', 'Artificial Control (moving mean, 1% window)');
    legend('Location', 'northeast');
    title('Artificial control envelope');
end


%% =====================================================================
% 9) CORRECT THE CONTROL (MAIN LOGIC LOOP)
% =====================================================================
% Goal:
%   Build a corrected control vector newControl with same length as signal.
% Rule (same as your previous runner):
%   - if abs(control - signal) is "too big", replace control with moving mean mSignal
%   - else keep original control
%
% The threshold uses mstdSignal and a hardcoded 0.1 scale (same as before).

control = controlRaw;   % rename for clarity (we will truncate this)

% Ensure equal length between signal and control (sometimes differ by 1)
n = min(numel(control), numel(signal));

% Truncate all arrays to length n
control     = control(1:n);
signal      = signal(1:n);
timeControl = timeControl(1:n);
timeSignal  = timeSignal(1:n);
mSignal     = mSignal(1:n);
mstdSignal  = mstdSignal(1:n);

% Preallocate corrected control
newControl = zeros(n, 1);

% Main correction loop (explicit, easy to debug)
for i = 1:n

    % Threshold expression (kept identical)
    threshold = abs(mSignal(i) - (mSignal(i) - 0.1 * mstdSignal(i)));

    % Compare control vs signal at same index
    if abs(control(i) - signal(i)) >= threshold
        % Replace with artificial control (moving mean)
        newControl(i) = mSignal(i);
    else
        % Keep real control
        newControl(i) = control(i);
    end
end

% Smooth corrected control (0.5% window; same expression as before)
newControl = movmean(newControl, 0.005 * size(newControl, 1));


%% =====================================================================
% 10) COMPUTE CORRECTED SIGNAL (ΔF/F) AND ZERO-CENTER
% =====================================================================

% Signal - control difference
diffSignalControl = signal - newControl;

% Relative difference (ΔF/F-like)
diffRelative = diffSignalControl ./ newControl;

% Zero-center (subtract mean)
diffRelativeZeroCentered = diffRelative - mean(diffRelative, 'omitnan');



% ---------------- Display-only scaling for plots (project rule) ----------------
% Keep saved data UNCHANGED (raw fraction, ΔF/F).
% Scale ONLY for plotting so values are readable (0.05 -> 5).
displayScale = 100;
diffRelative_plot = diffRelative * displayScale;
diffRelativeZeroCentered_plot = diffRelativeZeroCentered * displayScale;
%% =====================================================================
% 11) OPTIONAL MORE PLOTS (same content as before)
% =====================================================================
if showPlots

    % 11.1 Corrected control overlay
    figure('Name', 'FP correction - Corrected control', 'NumberTitle', 'off');
    plot(timeSignal, signal, 'DisplayName', 'Signal'); hold on;
    plot(timeControl, newControl, 'DisplayName', 'Corrected Control');
    xlabel('Time [s]');
    legend('Location', 'northeast');
    title('Corrected control');

    % 11.2 Signal minus control
    figure('Name', 'FP correction - Signal minus control', 'NumberTitle', 'off');
    plot(timeSignal, diffSignalControl, 'DisplayName', 'Signal - Control');
    xlabel('Time [s]');
    legend('Location', 'northeast');
    title('Subtraction of the control from the signal');

    % 11.3 dF/F (non-zero-centered)
    figure('Name', 'FP correction - dF/F', 'NumberTitle', 'off');
    plot(timeSignal, diffRelative_plot, 'DisplayName', '(Signal-Control)/Control'); hold on;
    grid on;

    % mean line as reference
    plot(timeSignal, mean(diffRelative_plot, 'omitnan') * ones(size(diffRelative_plot)), ...
        'HandleVisibility', 'off');

    xlabel('Time [s]');
    ylabel('Z-Score');
    legend('Location', 'northeast');
    title('(Signal-Control)/Control');

    % 11.4 dF/F zero-centered
    figure('Name', 'FP correction - dF/F zero-centered', 'NumberTitle', 'off');
    plot(timeSignal, diffRelativeZeroCentered_plot); hold on;
    grid on;

    plot(timeSignal, mean(diffRelativeZeroCentered_plot, 'omitnan') * ones(size(diffRelativeZeroCentered_plot)), ...
        'HandleVisibility', 'off');

    xlabel('Time [s]');
    ylabel('Z-Score');
    title('(Signal-Control)/Control zero-centered');
end


%% =====================================================================
% 12) CREATE OUTPUT TABLES (variable names kept the same)
% =====================================================================

% Legacy table (Var1/Var2 naming) - kept for backwards compatibility
tablediffRelative = array2table([timeSignal diffRelativeZeroCentered]); %#ok<NASGU>

% Preferred explicit table
correctedSignalTable = table(timeSignal, diffRelativeZeroCentered, ...
    'VariableNames', {'Time_s', 'CorrectedSignal'}); %#ok<NASGU>


%% =====================================================================
% 13) DECIDE OUTPUT FOLDER + SAVE MAT
% =====================================================================

% If outDir not provided, save next to the CSV
if strlength(outDir) == 0
    outDir = string(fileparts(photoCsv));
end

% Create output folder if missing
if ~isfolder(outDir)
    mkdir(outDir);
end

% Output file name based on the CSV file name
[~, baseName] = fileparts(photoCsv);
outMatName = sprintf('%s_CorrectedSignal.mat', baseName);
outMatFile = fullfile(outDir, outMatName);

% Keep this variable name in MAT (the app expects it)
sourcePhotometryCSV = char(photoCsv); %#ok<NASGU>

% Save variables
save(outMatFile, 'correctedSignalTable', 'tablediffRelative', 'sourcePhotometryCSV');

% Print message (same as before)
fprintf('[FP_signalCorrection_run] Saved corrected signal to: %s\n', outMatFile);

end
