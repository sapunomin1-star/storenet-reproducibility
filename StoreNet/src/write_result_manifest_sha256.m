function result = write_result_manifest_sha256(rootDirectory, options)
%WRITE_RESULT_MANIFEST_SHA256 Close and verify a result artifact tree.
%   RESULT = WRITE_RESULT_MANIFEST_SHA256(ROOT) recursively hashes every
%   file below ROOT in sorted repository-relative order. The checksum file
%   excludes itself and is verified by the cross-platform helper after writing.

arguments
    rootDirectory (1, 1) string
    options.FileName (1, 1) string = "RESULT_MANIFEST.sha256"
end

if ~isfolder(rootDirectory)
    error("StoreNet:ResultRootMissing", ...
        "Result root does not exist: %s", rootDirectory);
end
if contains(options.FileName, ["/", "\", newline]) || ...
        strlength(strip(options.FileName)) == 0
    error("StoreNet:InvalidResultManifestName", ...
        "FileName must be one plain, nonempty file name.");
end

manifestPath = string(fullfile(rootDirectory, options.FileName));
if isfile(manifestPath) || isfolder(manifestPath)
    error("StoreNet:ResultManifestExists", ...
        "Refusing to overwrite result checksum manifest: %s", manifestPath);
end

[relativePaths, absolutePaths] = recursiveFiles(rootDirectory, ...
    options.FileName);
if isempty(relativePaths)
    error("StoreNet:NoResultArtifacts", ...
        "No result artifacts were found below: %s", rootDirectory);
end

temporaryPath = string(tempname(rootDirectory)) + ".sha256";
fileId = fopen(temporaryPath, "wt", "n", "UTF-8");
if fileId < 0
    error("StoreNet:ResultManifestWriteFailed", ...
        "Unable to create temporary checksum manifest: %s", temporaryPath);
end
try
    for fileIndex = 1:numel(relativePaths)
        digest = sha256File(absolutePaths(fileIndex));
        fprintf(fileId, "%s  %s\n", char(digest), ...
            char(relativePaths(fileIndex)));
    end
catch exception
    fclose(fileId);
    deleteIfExists(temporaryPath);
    rethrow(exception)
end
fclose(fileId);
[moved, message] = movefile(temporaryPath, manifestPath);
if ~moved
    deleteIfExists(temporaryPath);
    error("StoreNet:ResultManifestWriteFailed", ...
        "Unable to finalize result checksum manifest: %s", message);
end

command = "storenetio.verifyManifest";
[status, output] = storenetio.verifyManifest(rootDirectory, manifestPath);
if status ~= 0
    error("StoreNet:ResultManifestVerificationFailed", ...
        "Result checksum verification failed (exit %d): %s", ...
        status, strtrim(string(output)));
end

verificationLines = strip(splitlines(string(output)));
verificationLines = verificationLines(strlength(verificationLines) > 0);
passedCount = nnz(endsWith(verificationLines, ": OK"));
if passedCount ~= numel(relativePaths)
    error("StoreNet:ResultManifestVerificationIncomplete", ...
        "Result checksum verification reported %d/%d passing files.", ...
        passedCount, numel(relativePaths));
end

result = struct;
result.rootDirectory = rootDirectory;
result.manifestPath = manifestPath;
result.entryCount = double(numel(relativePaths));
result.relativePaths = relativePaths;
result.verificationCommand = command;
result.verificationExitStatus = double(status);
result.verificationPassedCount = double(passedCount);
result.verificationPassed = true;
result.verificationOutput = strtrim(string(output));
end

function [relativePaths, absolutePaths] = recursiveFiles(rootDirectory, ...
        excludedFileName)
entries = dir(fullfile(rootDirectory, "**", "*"));
entries = entries(~[entries.isdir]);
absolutePaths = string(fullfile({entries.folder}, {entries.name})).';
prefix = string(rootDirectory);
if ~endsWith(prefix, filesep)
    prefix = prefix + filesep;
end
if any(~startsWith(absolutePaths, prefix))
    error("StoreNet:ResultArtifactOutsideRoot", ...
        "An enumerated result artifact is outside the requested root.");
end
relativePaths = extractAfter(absolutePaths, strlength(prefix));
relativePaths = replace(relativePaths, filesep, "/");
isChecksumFile = relativePaths == excludedFileName;
relativePaths(isChecksumFile) = [];
absolutePaths(isChecksumFile) = [];
if any(contains(relativePaths, newline))
    error("StoreNet:UnsupportedResultPath", ...
        "Result artifact paths containing newlines are unsupported.");
end
[relativePaths, order] = sort(relativePaths);
absolutePaths = absolutePaths(order);
end

function digest = sha256File(path)
digest = storenetio.hashFile(path);
end

function deleteIfExists(path)
if isfile(path)
    delete(path);
end
end
