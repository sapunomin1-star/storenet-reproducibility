function digest = hashFile(path)
%HASHFILE Calculate a file's SHA-256 on macOS, Windows and Linux.
arguments
    path (1, 1) string
end
if ~isfile(path)
    error("StoreNet:HashFileMissing", "Cannot read file: %s", path);
end
quoted = storenetio.shellQuote(path);
if ispc
    command = "certutil -hashfile " + quoted + " SHA256";
elseif ismac
    command = "/usr/bin/shasum -a 256 -- " + quoted;
else
    command = "sha256sum -- " + quoted;
end
[status, output] = system(command);
token = regexp(output, '(?m)^([0-9a-fA-F]{64})(?:\s|$)', 'tokens', 'once');
if status ~= 0 || isempty(token)
    error("StoreNet:HashReadFailed", "Cannot verify %s: %s", path, strtrim(output));
end
digest = lower(string(token{1}));
end
