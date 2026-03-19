function tf = safe_isfolder(p)
% safe_isfolder  True if p points to an existing folder (safe, no crashes).
% -------------------------------------------------------------------------
% WHY THIS EXISTS
%   MATLAB's isfolder() can throw errors or behave unexpectedly if you pass:
%     - [] (empty)
%     - 0 (uigetdir cancel)
%     - "" (empty string)
%     - a cell array (sometimes you store paths in cells)
%
% This helper returns FALSE instead of crashing.
%
% INPUT
%   p : folder path (char, string, or cell containing one path)
%
% OUTPUT
%   tf : true if p is a valid existing folder, otherwise false
% -------------------------------------------------------------------------

%% 1) Default output
tf = false;

%% 2) Safe checks
try
    if nargin < 1
        return;
    end

    if isempty(p)
        return;
    end

    % uigetdir returns 0 when cancelled
    if isnumeric(p)
        return;
    end

    % If cell, unwrap first element
    if iscell(p)
        if isempty(p)
            return;
        end
        p = p{1};
        if isempty(p)
            return;
        end
    end

    % Convert string -> char
    if isstring(p)
        if numel(p) ~= 1
            return;
        end
        if strlength(p) == 0
            return;
        end
        p = char(p);
    end

    % Only accept char path
    if ~ischar(p)
        return;
    end

    if isempty(p)
        return;
    end

    % Actual folder existence test
    tf = isfolder(p);

catch
    tf = false;
end

end
