function fixture = writeAusgridFixture(rootFolder, options)
%WRITEAUSGRIDFIXTURE Write a release-shaped Ausgrid CSV and JSON spec.
%   This helper centralizes fixture construction so class test methods can
%   remain pure Arrange-Act-Assert without control-flow logic.

arguments
    rootFolder (1, 1) string
    options.Mode (1, 1) string {mustBeMember(options.Mode, ...
        ["valid", "bad-quality", "missing-required", ...
        "duplicate-required", "duplicate-optional", "negative", ...
        "missing-interval"])} = "valid"
end

if ~isfolder(rootFolder)
    mkdir(rootFolder);
end

sourceFile = fullfile(rootFolder, "ausgrid_fixture.csv");
specPath = fullfile(rootFolder, "ausgrid_fixture.json");
targetDay = datetime(2012, 7, 2);
customerIds = [101, 102];
intervalNames = makeIntervalNames();
headers = ["Customer", "Generator Capacity", "Postcode", ...
    "Consumption Category", "date", intervalNames, "Row Quality"];

fileId = fopen(sourceFile, "w");
if fileId < 0
    error("writeAusgridFixture:CannotCreateCsv", ...
        "Cannot create fixture CSV: %s", sourceFile);
end
cleanup = onCleanup(@() fclose(fileId));
fprintf(fileId, '"Synthetic Ausgrid fixture"%s\n', repmat(',', 1, 53));
fprintf(fileId, '%s\n', strjoin(headers, ','));

fixtureDays = datetime(2012, 7, 1):caldays(1):datetime(2013, 6, 30);
for dayValue = fixtureDays
    for customerId = customerIds
        categories = categoriesForCustomer(customerId);
        for category = categories
            if shouldSkip(options.Mode, dayValue, targetDay, ...
                    customerId, category)
                continue
            end
            [values, rowQuality, blankInterval] = fixtureRowValues( ...
                options.Mode, dayValue, targetDay, customerId, category);
            writeRow(fileId, customerId, category, dayValue, values, ...
                rowQuality, blankInterval);
            if shouldDuplicate(options.Mode, dayValue, targetDay, ...
                    customerId, category)
                writeRow(fileId, customerId, category, dayValue, values, ...
                    rowQuality, blankInterval);
            end
        end
    end
end
clear cleanup

spec = fixtureSpec(sourceFile, customerIds);
specFileId = fopen(specPath, "w");
if specFileId < 0
    error("writeAusgridFixture:CannotCreateSpec", ...
        "Cannot create fixture specification: %s", specPath);
end
specCleanup = onCleanup(@() fclose(specFileId));
fprintf(specFileId, '%s\n', jsonencode(spec, PrettyPrint=true));
clear specCleanup

fixture = struct;
fixture.Root = rootFolder;
fixture.SourceFile = string(sourceFile);
fixture.SpecPath = string(specPath);
fixture.TargetDay = targetDay;
fixture.CustomerIds = customerIds;
fixture.Mode = options.Mode;
end

function categories = categoriesForCustomer(customerId)
if customerId == 101
    categories = ["CL", "GC", "GG"];
else
    categories = ["GC", "GG"];
end
end

function names = makeIntervalNames()
names = strings(1, 48);
for intervalIndex = 1:48
    totalMinutes = 30 * intervalIndex;
    names(intervalIndex) = string(sprintf("%d:%02d", ...
        mod(floor(totalMinutes / 60), 24), mod(totalMinutes, 60)));
end
end

function skip = shouldSkip(mode, dayValue, targetDay, customerId, category)
skip = mode == "missing-required" && dayValue == targetDay && ...
    customerId == 102 && category == "GG";
end

function duplicate = shouldDuplicate(mode, dayValue, targetDay, ...
        customerId, category)
duplicateRequired = mode == "duplicate-required" && ...
    dayValue == targetDay && customerId == 101 && category == "GC";
duplicateOptional = mode == "duplicate-optional" && ...
    dayValue == targetDay && customerId == 101 && category == "CL";
duplicate = duplicateRequired || duplicateOptional;
end

function [values, quality, blankInterval] = fixtureRowValues( ...
        mode, dayValue, targetDay, customerId, category)
values = categoryEnergy(category) * ones(1, 48);
quality = "";
blankInterval = 0;
isTargetRow = dayValue == targetDay && customerId == 101 && ...
    category == "GG";
if mode == "bad-quality" && isTargetRow
    quality = "NA";
elseif mode == "negative" && isTargetRow
    values(1) = -0.1;
elseif mode == "missing-interval" && isTargetRow
    blankInterval = 7;
end
end

function energy = categoryEnergy(category)
switch category
    case "GC"
        energy = 0.5;
    case "GG"
        energy = 0.1;
    otherwise
        energy = 0.25;
end
end

function writeRow(fileId, customerId, category, dayValue, values, ...
        rowQuality, blankInterval)
capacity = 3.5 + (customerId == 102) * 0.5;
postcode = 2000 + customerId;
valueText = compose("%.6f", values(:).');
if blankInterval > 0
    valueText(blankInterval) = "";
end
fields = [string(customerId), string(capacity), string(postcode), ...
    category, string(dayValue, "dd/MM/yyyy"), valueText, rowQuality];
fprintf(fileId, '%s\n', strjoin(fields, ','));
end

function spec = fixtureSpec(sourceFile, customerIds)
spec = struct;
spec.schemaVersion = "StoreNet-cross-environment-spec-v1";
spec.datasetId = "ausgrid-solar-home-2012-2013";
spec.title = "Synthetic Ausgrid fixture";
spec.datasetPaperDoi = "fixture";
spec.officialMetadataUrl = "https://example.test/metadata";
spec.archiveUrl = "https://example.test/archive";
spec.archiveLicense = "CC BY 3.0 AU";
spec.releaseManifestPath = "AUSGRID_MANIFEST.sha256";
spec.sourceFile = string(sourceFile);
spec.sourceFileSha256 = repmat('0', 1, 64);
spec.sourceIntervalMinutes = 30;
spec.timestampBasis = ...
    "naive Sydney local wall clock as released; interval-end labels";
spec.energyUnit = "kWh per 30-minute interval";
spec.loadDefinition = "GC + optional CL";
spec.pvDefinition = ...
    "GG; separately metered inverter-AC gross generation";
spec.publishedCleanCustomerIds = customerIds;
spec.excludedCustomerIds = zeros(1, 0);
spec.exclusionReason = "fixture";
spec.analysisCustomerIds = customerIds;
spec.qualityContract = struct( ...
    requiredCategories=["GC", "GG"], optionalCategories="CL", ...
    acceptedRowQuality="blank only", imputation="none", ...
    rejectWholeCommunityDay=true);
spec.fixedPolicyTransfer = struct(etaPvAC=1, etaPvDC=0.95, ...
    etaBatteryCharge=0.95, etaBatteryDischarge=0.95, ...
    transferLossFraction=0.07, batteryCapacityKWhPerHome=10, ...
    batteryPowerKWPerHome=3.3, nightPrice=0.091, dayPrice=0.194, ...
    dayStartHour=10, dayEndHour=22, feedInPrice=0);
spec.primarySelection = struct( ...
    method="one robust central day per calendar month", ...
    features="48 aggregate-load plus 48 aggregate-PV values", ...
    standardization="coordinate-wise median and MAD within month", ...
    tieBreak="earliest date", optimizationOutcomesUsed=false);
end
