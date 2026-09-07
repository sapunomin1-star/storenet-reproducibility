classdef TestPortableFiles < matlab.unittest.TestCase
    %TESTPORTABLEFILES File integrity and Unicode paths on supported systems.
    properties
        Folder
        File
        Manifest
    end
    methods (TestClassSetup)
        function addSource(testCase)
            source = fullfile(fileparts(fileparts(mfilename("fullpath"))), "src");
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture(source));
        end
    end
    methods (TestMethodSetup)
        function createFiles(testCase)
            testCase.Folder = string(tempname) + " 中文 空白";
            mkdir(testCase.Folder);
            testCase.addTeardown(@() rmdir(testCase.Folder, "s"));
            testCase.File = fullfile(testCase.Folder, "資料 abc.bin");
            writeBytes(testCase.File, uint8('abc'));
            testCase.Manifest = fullfile(testCase.Folder, "manifest.sha256");
            writelines("ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad  資料 abc.bin", ...
                testCase.Manifest, Encoding="UTF-8");
        end
    end
    methods (Test)
        function knownDigestWithUnicodePath(testCase)
            digest = storenetio.hashFile(testCase.File);
            testCase.verifyEqual(digest, ...
                "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad");
        end
        function validManifestPasses(testCase)
            [status, output] = storenetio.verifyManifest(testCase.Folder, testCase.Manifest);
            testCase.verifyEqual(status, 0);
            testCase.verifyEqual(output, "資料 abc.bin: OK");
        end
        function equalLengthModificationFails(testCase)
            writeBytes(testCase.File, uint8('abd'));
            [status, output] = storenetio.verifyManifest(testCase.Folder, testCase.Manifest);
            testCase.verifyEqual(status, 1);
            testCase.verifyEqual(output, "資料 abc.bin: FAILED");
        end
        function missingFileFails(testCase)
            delete(testCase.File);
            [status, output] = storenetio.verifyManifest(testCase.Folder, testCase.Manifest);
            testCase.verifyEqual(status, 1);
            testCase.verifyEqual(output, "資料 abc.bin: FAILED");
        end
    end
end

function writeBytes(path, bytes)
fileId = fopen(path, "wb");
cleanup = onCleanup(@() fclose(fileId));
fwrite(fileId, bytes, "uint8");
end
