function [status, output] = verifyManifest(root, manifestPath)
%VERIFYMANIFEST Check SHA-256 entries without an operating-system command.
% Returns a status code and one "path: OK" or "path: FAILED" line per file.
arguments
    root (1, 1) string
    manifestPath (1, 1) string
end
status = 1;
if ~isfile(manifestPath)
    output = "Manifest missing: " + manifestPath;
    return
end
lines = strip(readlines(manifestPath, Encoding="UTF-8"));
lines = lines(strlength(lines) > 0 & ~startsWith(lines, "#"));
if isempty(lines)
    output = "Manifest contains no files.";
    return
end
messages = strings(numel(lines), 1);
passed = false(numel(lines), 1);
for index = 1:numel(lines)
    token = regexp(char(lines(index)), ...
        '^([0-9A-Fa-f]{64})\s+\*?(.+)$', 'tokens', 'once');
    if isempty(token)
        messages(index) = "Invalid manifest entry: " + lines(index);
        continue
    end
    relative = string(token{2});
    try
        passed(index) = storenetio.hashFile(fullfile(root, relative)) == ...
            lower(string(token{1}));
    catch exception
        if ~startsWith(string(exception.identifier), "StoreNet:Hash")
            rethrow(exception)
        end
        % Missing or unreadable files fail verification; other entries continue.
    end
    if passed(index)
        messages(index) = relative + ": OK";
    else
        messages(index) = relative + ": FAILED";
    end
end
status = double(~all(passed));
output = join(messages, newline);
end
