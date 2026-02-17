function tf = safe_isfile(p)
% safe_isfile  True if p points to an existing file (safe, no crashes).
% -------------------------------------------------------------------------
% WHY THIS EXISTS
%   MATLAB's isfile() can throw errors if you pass:
%     - [] (empty)
%     - 0 (uigetfile cancel)
%     - "" (empty string)
%     - a cell array (sometimes you store paths in cells)
%
% This helper returns FALSE instead of crashing.
%
% INPUT
%   p : file path (char, string, or cell containing one path)
%
% OUTPUT
%   tf : true if p is a valid existing file, otherwise false
% -------------------------------------------------------------------------

%% 1) Default output
tf = false;

%% 2) Quick reject for empty inputs
try
    if nargin < 1
        return;
    end

    if isempty(p)
        return;
    end

    %% 3) Handle "cancel" values from file dialogs
    % uigetfile returns 0 when cancelled.
    if isnumeric(p)
        % p could be 0, or some numeric array (not a path)
        return;
    end

    %% 4) If input is a cell, try to use the first element
    if iscell(p)
        if isempty(p)
            return;
        end

        % Often the path is stored as { 'C:\...\file.csv' }
        p = p{1};

        % If it is still empty after unwrapping
        if isempty(p)
            return;
        end
    end

    %% 5) Convert string -> char (for older MATLAB compatibility)
    if isstring(p)
        % Only accept scalar strings
        if numel(p) ~= 1
            return;
        end

        if strlength(p) == 0
            return;
        end

        p = char(p);
    end

    %% 6) Final check: only char is accepted as a path here
    if ~ischar(p)
        return;
    end

    if isempty(p)
        return;
    end

    %% 7) Actual file existence test
    tf = isfile(p);

catch
    tf = false;
end

end
