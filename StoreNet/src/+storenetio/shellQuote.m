function quoted = shellQuote(value)
%SHELLQUOTE Quote one path argument for optional Git provenance commands.
arguments
    value (1, 1) string
end
if contains(value, [newline, char(13), char(0)])
    error("StoreNet:UnsupportedShellPath", "A path contains control characters.");
end
if ispc
    if contains(value, ["%", "!", char(34)])
        error("StoreNet:UnsupportedShellPath", ...
            "Git path contains unsupported Windows shell characters: %s", value);
    end
    quoted = string(char(34)) + value + string(char(34));
else
    single = char(39);
    double = char(34);
    escaped = [single, double, single, double, single];
    quoted = string([single, strrep(char(value), single, escaped), single]);
end
end
