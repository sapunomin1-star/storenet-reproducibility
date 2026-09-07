function makeSyntheticData(dataRoot, day, variant)
%MAKESYNTHETICDATA Create a deterministic 20-home release-shaped fixture.
arguments
    dataRoot (1, 1) string
    day (1, 1) datetime
    variant (1, 1) string {mustBeMember(variant, ...
        ["complete", "status-gap", "missing-wh"])}
end

mkdir(dataRoot);
day = dateshift(day, "start", "day");
wTime = (day:minutes(1):day + days(1)).';
whTime = (day + minutes(1):minutes(1):day + days(1)).';
pvHomes = [1, 2, 3, 4, 5, 7, 10, 11, 13, 17];

for homeIndex = 1:20
    home = "H" + homeIndex;
    isPvHome = ismember(homeIndex, pvHomes);
    status = ones(numel(wTime), 1);
    if variant == "status-gap" && homeIndex == 1
        status(wTime == day + hours(12)) = NaN;
    end

    zerosW = zeros(numel(wTime), 1);
    productionW = double(isPvHome) * 300 * ones(numel(wTime), 1);
    consumptionW = 600 * ones(numel(wTime), 1);
    socW = 10 * ones(numel(wTime), 1);
    w = table(wTime, zerosW, zerosW, productionW, consumptionW, socW);
    w.Properties.VariableNames = ["date", " Discharge(W)", " Charge(W)", ...
        " Production(W)", " Consumption(W)", " State of Charge(%)"];
    if homeIndex == 4
        w.("Unnamed: 6") = nan(height(w), 1);
    end
    w.(home + "_W") = status;

    zerosWh = zeros(numel(whTime), 1);
    productionWh = double(isPvHome) * 5 * ones(numel(whTime), 1);
    consumptionWh = 10 * ones(numel(whTime), 1);
    fromGridWh = consumptionWh - productionWh;
    socWh = 10 * ones(numel(whTime), 1);
    wh = table(whTime, zerosWh, zerosWh, productionWh, ...
        consumptionWh, zerosWh, fromGridWh, socWh);
    wh.Properties.VariableNames = ["date", " Discharge(Wh)", ...
        " Charge(Wh)", " Production(Wh)", " Consumption(Wh)", ...
        " Feed-in(Wh)", " From grid(Wh)", " State of Charge(%)"];
    if variant == "missing-wh" && homeIndex == 1
        wh(whTime == day + hours(12) + minutes(15), :) = [];
    end

    w.date.Format = "yyyy-MM-dd HH:mm:ss";
    wh.date.Format = "yyyy-MM-dd HH:mm:ss";
    writetable(w, fullfile(dataRoot, home + "_W.csv"));
    writetable(wh, fullfile(dataRoot, home + "_Wh.csv"));
end
end
