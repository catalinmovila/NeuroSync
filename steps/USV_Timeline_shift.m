function out = USV_Timeline_shift(varargin)
% USV_Timeline_shift  (PASS 2: extra-declustered + heavy comments)
% -------------------------------------------------------------------------
% App-safe wrapper to shift DeepSqueak USV times into the TTLBox/FP timebase.
%
% Mapping model:
%   t_TTLBox = a * t_audio + b
%
% This function is the "Apply USV shift" button wrapper.
% The heavy work is done in:
% PASS 2 NOTE:
%   If you want to understand/modify the actual shifting algorithm,
%   read USV_Timeline_shift_run.m (this file is mostly argument handling).

%   USV_Timeline_shift_run.m
%
% --------------------------
% CALL PATTERNS
% --------------------------
% 1) App / non-interactive (recommended)
%   out = USV_Timeline_shift(syncMapXlsx, usvMat);
%
% 2) App / non-interactive with options
%   out = USV_Timeline_shift(syncMapXlsx, usvMat, ...
%        'Overwrite', false, ...
%        'OutMat', 'C:\...\MyDetection_SHIFTED.mat', ...
%        'Verbose', true);
%
% 3) Interactive (uses file pickers)
%   out = USV_Timeline_shift('Interactive', true);
%
% --------------------------
% OUTPUT
% --------------------------
% out is a struct:
%   out.a, out.b           : mapping coefficients
%   out.inMat              : input MAT
%   out.outMat             : output MAT written
%   out.overwrite          : logical
%   out.syncMappingXlsx    : mapping file used
%
% NOTE ABOUT OPTIONS
%   The original version used inputParser with KeepUnmatched=true, meaning
%   unknown Name-Value options were ignored. This declustered version keeps
%   that behavior: unknown options are ignored.
% -------------------------------------------------------------------------

%% -------------------- 1) Defaults --------------------
mapFile = "";
usvMat  = "";

args = struct();
args.Interactive = false;
args.Overwrite   = false;
args.OutMat      = "";
args.Verbose     = true;

%% -------------------- 2) Parse positional inputs if present --------------------
% Accept positional usage: (mapFile, usvMat, ...)
nv = varargin;

if ~isempty(nv)
    a1 = nv{1};
    if localIsText(a1)
        s1 = string(a1);
        % "looks like map" if it ends with .xlsx OR the file exists
        looksLikeMap = endsWith(lower(s1), ".xlsx") || isfile(s1);
        if looksLikeMap
            mapFile = s1;
            nv(1) = [];

            if ~isempty(nv)
                a2 = nv{1};
                if localIsText(a2)
                    s2 = string(a2);
                    looksLikeMat = endsWith(lower(s2), ".mat") || isfile(s2);
                    if looksLikeMat
                        usvMat = s2;
                        nv(1) = [];
                    end
                end
            end
        end
    end
end

%% -------------------- 3) Parse Name-Value options (simple, beginner style) --------------------
if ~isempty(nv)
    if mod(numel(nv),2) ~= 0
        error('USV_Timeline_shift:BadArgs', 'Name-Value inputs must come in pairs.');
    end

    k = 1;
    while k <= numel(nv)
        name  = nv{k};
        value = nv{k+1};

        if ~localIsText(name)
            error('USV_Timeline_shift:BadArgs', 'Option name at position %d must be text.', k);
        end

        key = lower(strtrim(string(name)));

        if key == "interactive"
            args.Interactive = logical(value) && isscalar(value);

        elseif key == "overwrite"
            args.Overwrite = logical(value) && isscalar(value);

        elseif key == "outmat"
            % Accept char or string
            if localIsText(value)
                args.OutMat = string(value);
            else
                args.OutMat = "";
            end

        elseif key == "verbose"
            args.Verbose = logical(value) && isscalar(value);

        else
            % KeepUnmatched behavior: ignore unknown options
            % (do nothing)
        end

        k = k + 2;
    end
end

%% -------------------- 4) Interactive pickers if requested --------------------
if args.Interactive
    if strlength(mapFile) == 0
        [fM, pM] = uigetfile({'*.xlsx','SYNC_MAPPING (*.xlsx)'}, 'Select *_SYNC_MAPPING.xlsx');
        if isequal(fM,0)
            error('USV_Timeline_shift:Canceled', 'No mapping selected.');
        end
        mapFile = string(fullfile(pM, fM));
    end

    if strlength(usvMat) == 0
        [fU, pU] = uigetfile({'*.mat','USV detection MAT (*.mat)'}, 'Select DeepSqueak USV detection MAT');
        if isequal(fU,0)
            error('USV_Timeline_shift:Canceled', 'No USV MAT selected.');
        end
        usvMat = string(fullfile(pU, fU));
    end
end

%% -------------------- 5) Validate inputs --------------------
if strlength(mapFile) == 0 || ~isfile(mapFile)
    error('USV_Timeline_shift:MissingMap', 'SYNC_MAPPING.xlsx not found.');
end

if strlength(usvMat) == 0 || ~isfile(usvMat)
    error('USV_Timeline_shift:MissingUSV', 'USV MAT not found.');
end

%% -------------------- 6) Call underlying run function --------------------
try
    if strlength(args.OutMat) > 0
        [outMat, a, b] = USV_Timeline_shift_run(mapFile, usvMat, ...
            'OutMat', args.OutMat, ...
            'Overwrite', args.Overwrite);
    else
        [outMat, a, b] = USV_Timeline_shift_run(mapFile, usvMat, ...
            'Overwrite', args.Overwrite);
    end
catch ME
    ME2 = MException('USV_Timeline_shift:RunFailed', ...
        'USV timeline shift failed: %s', ME.message);
    ME2 = ME2.addCause(ME);
    throw(ME2);
end

%% -------------------- 7) Print info (optional) --------------------
if args.Verbose
    fprintf('[USV_Timeline_shift] a=%.12g, b=%.12g s\n', a, b);

    if args.Overwrite
        fprintf('Overwrote: %s\n', char(string(usvMat)));
    else
        fprintf('Wrote:     %s\n', char(string(outMat)));
    end
end

%% -------------------- 8) Output struct for the App --------------------
out = struct();
out.a = a;
out.b = b;
out.inMat = char(string(usvMat));
out.outMat = char(string(outMat));
out.overwrite = logical(args.Overwrite);
out.syncMappingXlsx = char(string(mapFile));

end

%% ========================= Local helpers =========================

function tf = localIsText(x)
tf = ischar(x) || isstring(x);
end
