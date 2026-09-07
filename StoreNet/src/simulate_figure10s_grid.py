"""Figure 10-S: auditable, independent StoreNet + IEEE European LV simulation.

Run with ../.venv-grid/bin/python. This does not reproduce the unpublished
Saif network model and never modifies author data or the existing report.
"""
from __future__ import annotations

import argparse
import hashlib
import importlib.metadata
import json
from pathlib import Path
import re
import sys

import numpy as np
import pandas as pd
from scipy.optimize import linprog
from scipy.sparse import lil_matrix
from opendssdirect import dss
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib import font_manager

ROOT = Path(__file__).resolve().parents[1]
FEEDER = ROOT / "data/external/ieee_european_lv"
CONFIG = ROOT / "config/figure10s_grid.json"
LABELS = {"POOL_FLAT": "冬日／固定電價", "POOL_TOU": "夏日／日夜電價"}


def sha(path):
    h = hashlib.sha256()
    with Path(path).open("rb") as f:
        for block in iter(lambda: f.read(1024 * 1024), b""):
            h.update(block)
    return h.hexdigest()


def log(message):
    print(message, flush=True)


def verify_feeder_inputs():
    for directory in [FEEDER, FEEDER / 'ieee_primary_csv']:
        record=json.loads((directory/'來源紀錄.json').read_text(encoding="utf-8"))
        for file in record['files']:
            if sha(directory/file['file']) != file['sha256']:
                raise ValueError(f"Feeder input changed: {file['file']}")
    # Cross-check the OpenDSS mirror topology with the IEEE-owned CSV release.
    primary=pd.read_csv(FEEDER/'ieee_primary_csv/Lines.csv',comment='#').dropna(how='all')
    actual={}
    for line in (FEEDER/'Lines.txt').read_text(encoding="utf-8").splitlines():
        m=re.search(r'Line\.(\w+) Bus1=(\w+) Bus2=(\w+).*Linecode=(\S+) Length=(\S+) Units=(\w+)',line,re.I)
        if m:actual[m[1].upper()]=m.groups()[1:]
    assert len(primary)==len(actual)
    for r in primary.itertuples():
        bus1,bus2,code,length,unit=actual[r.Name.upper()]
        assert int(bus1)==int(r.Bus1) and int(bus2)==int(r.Bus2)
        assert code.lower()==r.LineCode.lower() and unit==r.Units
        assert abs(float(length)-r.Length)<1e-8
    primary_loads=pd.read_csv(FEEDER/'ieee_primary_csv/Loads.csv',comment='#').dropna(how='all')
    mp=mapping()
    for p,r in zip(primary_loads.itertuples(),mp.itertuples()):
        assert p.Name.lower()==r.LoadName and str(int(p.Bus))==r.Bus
        assert 'ABC'.index(p.phases)+1==r.Phase
    assert len(primary_loads)==55
    return {'IEEELinesMatched':len(actual),'IEEECustomerConnectionsMatched':55}


def load_profiles(out):
    """Only retain January/June, audit every hourly processed sample count."""
    cache = ROOT / "data/derived/figure10s_hourly_jan_jun.csv"
    meta = cache.with_suffix(".json")
    files = [ROOT / f"data/raw/H{i}_Wh.csv" for i in range(1, 21)]
    hashes = {p.name: sha(p) for p in files}
    if cache.exists() and meta.exists() and json.loads(meta.read_text(encoding="utf-8")).get("inputs") == hashes:
        log("使用已核對來源雜湊的每小時資料快取。")
        hourly = pd.read_csv(cache, parse_dates=["Time"])
    else:
        records = []
        for house, path in enumerate(files, 1):
            log(f"讀取並檢查 H{house:02d} 的一月、六月資料（{house}/20）")
            pieces = []
            for chunk in pd.read_csv(path, usecols=lambda s: s.strip() in
                                     {"date", "Consumption(Wh)", "Production(Wh)"}, chunksize=150000):
                chunk.columns = chunk.columns.str.strip()
                take = chunk["date"].str.startswith(("2020-01-", "2020-06-"))
                if take.any():
                    pieces.append(chunk.loc[take].copy())
            frame = pd.concat(pieces, ignore_index=True)
            frame["Time"] = pd.to_datetime(frame.pop("date"), errors="raise")
            if frame["Time"].duplicated().any():
                raise ValueError(f"H{house}: duplicate timestamps")
            frame = frame.set_index("Time").sort_index()
            for col in ["Consumption(Wh)", "Production(Wh)"]:
                frame[col] = pd.to_numeric(frame[col], errors="raise")
            finite = np.isfinite(frame.to_numpy()).all(axis=1) & (frame.to_numpy() >= 0).all(axis=1)
            frame["FiniteNonnegative"] = finite.astype(int)
            frame["MinuteAligned"] = ((frame.index.second == 0) & (frame.index.microsecond == 0)).astype(int)
            group = frame.resample("h")
            h = pd.DataFrame({"LoadKW": group["Consumption(Wh)"].sum(min_count=60) / 1000,
                              "PVKW": group["Production(Wh)"].sum(min_count=60) / 1000,
                              "FiniteMinutes": group["FiniteNonnegative"].sum(),
                              "AlignedMinutes": group["MinuteAligned"].sum(),
                              "Rows": group.size()})
            h = h[h.index.month.isin([1, 6])]
            h["House"] = house
            records.append(h.reset_index())
        hourly = pd.concat(records, ignore_index=True)
        cache.parent.mkdir(parents=True, exist_ok=True)
        hourly.to_csv(cache, index=False)
        meta.write_text(json.dumps({"inputs": hashes, "definition": "sum of 60 minute Wh / 1000 = average kW over one hour"}, indent=2), encoding="utf-8")
    hourly["Date"] = hourly["Time"].dt.strftime("%Y-%m-%d")
    hourly["ValidHour"] = (hourly["FiniteMinutes"].eq(60) & hourly["AlignedMinutes"].eq(60)
                            & hourly["Rows"].eq(60) & np.isfinite(hourly[["LoadKW", "PVKW"]]).all(axis=1))
    days = hourly.groupby("Date").agg(ValidHours=("ValidHour", "sum"), Rows=("House", "size"),
                                      TotalLoadKWh=("LoadKW", "sum"))
    days["TotalPVKWh"] = hourly[hourly["House"] <= 10].groupby("Date")["PVKW"].sum()
    days["Complete20Processed"] = days["ValidHours"].eq(480) & days["Rows"].eq(480)
    valid = days[days["Complete20Processed"]]
    winter = valid.loc[valid.index.str.startswith("2020-01"), "TotalLoadKWh"].idxmax()
    summer = valid.loc[valid.index.str.startswith("2020-06"), "TotalPVKWh"].idxmax()
    days["Selected"] = days.index.isin([winter, summer])
    days.to_csv(out / "代表日選擇與資料完整性.csv", encoding="utf-8-sig")
    selected = hourly[hourly["Date"].isin([winter, summer])].copy()
    selected.to_csv(out / "來源20戶_每小時負載與太陽能.csv", index=False, encoding="utf-8-sig")
    return selected, {"winter": winter, "summer": summer}, hashes


def mapping():
    rows = []
    for line in (FEEDER / "Loads.txt").read_text(encoding="utf-8").splitlines():
        m = re.search(r"Load\.LOAD(\d+).*Bus1=(\d+)\.(\d+)", line, re.I)
        if m:
            i, bus, phase = map(int, m.groups())
            rows.append({"Customer": i, "LoadName": f"load{i}", "Bus": str(bus), "Phase": phase})
    frame = pd.DataFrame(rows).sort_values("Customer").reset_index(drop=True)
    assert len(frame) == 55
    frame["LoadHouse"] = np.resize(np.arange(1,21),55)
    frame["PVHouse"] = np.resize(np.arange(1,11),55)
    return frame


def day_arrays(profiles, date, mp):
    h = profiles[profiles["Date"] == date]
    load = h.pivot(index="Time", columns="House", values="LoadKW")
    pv = h.pivot(index="Time", columns="House", values="PVKW")
    assert len(load) == 24 and len(pv) == 24
    return load.loc[:, mp.LoadHouse].to_numpy(), pv.loc[:, mp.PVHouse].to_numpy()


def optimise(load, pv, tariff, cfg):
    """Lossless community LP, also exercised on one-customer known tests."""
    T, N = load.shape; M = T * N
    ci = np.arange(M).reshape(T, N); di = ci + M
    ei = np.arange((T + 1) * N).reshape(T + 1, N) + 2 * M
    gi = np.arange(T) + 2 * M + (T + 1) * N; xi = gi + T
    nv = int(xi[-1] + 1)
    eq = lil_matrix((M + T, nv)); rhs = np.zeros(M + T)
    eta_c, eta_d = cfg["charge_efficiency"], cfg["discharge_efficiency"]
    for t in range(T):
        for n in range(N):
            k = t * N + n
            eq[k, ei[t+1,n]] = 1; eq[k, ei[t,n]] = -1
            eq[k, ci[t,n]] = -eta_c; eq[k, di[t,n]] = 1 / eta_d
        eq[M+t, gi[t]] = 1; eq[M+t, xi[t]] = -1
        eq[M+t, ci[t]] = -1; eq[M+t, di[t]] = 1
        rhs[M+t] = (load[t] - pv[t]).sum()
    bounds = [(0, cfg["battery_power_kw"])] * (2*M)
    bounds += [(cfg["battery_min_kwh"], cfg["battery_max_kwh"])] * ((T+1)*N)
    bounds += [(0, None)] * (2*T)
    for i in np.r_[ei[0], ei[-1]]:
        bounds[int(i)] = (cfg["battery_initial_final_kwh"], cfg["battery_initial_final_kwh"])
    cost = np.zeros(nv); cost[gi] = tariff; cost[xi] = -cfg["export_eur_kwh"]
    eq = eq.tocsr()
    first = linprog(cost, A_eq=eq, b_eq=rhs, bounds=bounds, method="highs")
    if not first.success: raise RuntimeError(first.message)
    tie = np.zeros(nv)
    tie[:2*M] = 1 + np.arange(2*M) * 1e-7 / max(1, 2*M)
    second = linprog(tie, A_ub=cost.reshape(1,-1), b_ub=[first.fun + cfg["primary_cost_tolerance_eur"]],
                     A_eq=eq, b_eq=rhs, bounds=bounds, method="highs")
    if not second.success: raise RuntimeError(second.message)
    x = second.x; c = x[ci]; d = x[di]; e = x[ei]
    residual = float(np.max(np.abs(eq @ x - rhs)))
    simultaneous = float(np.minimum(c,d).max())
    assert residual < 1e-6 and simultaneous < 1e-6, (residual, simultaneous)
    assert float(cost @ x - first.fun) < cfg["primary_cost_tolerance_eur"] + 1e-6
    return c, d, e, {"BestBillEUR": float(first.fun), "BillEUR": float(cost @ x),
                      "LPResidual": residual, "SimultaneousChargeDischargeKW": simultaneous}


def schedule(load, pv, case, cfg):
    tariff = np.full(24, cfg["flat_eur_kwh"])
    if case.endswith("TOU"):
        tariff[:] = cfg["tou_day_eur_kwh"]
        tariff[cfg["tou_night_start_hour"]:cfg["tou_night_end_hour_exclusive"]] = cfg["tou_night_eur_kwh"]
    c, d, e, metrics = optimise(load, pv, tariff, cfg)
    return c, d, e, metrics, tariff


def compile_feeder(cfg, mp):
    dss.Basic.ClearAll()
    dss.Basic.AllowChangeDir(False)
    for cmd in ["set defaultbasefrequency=50", "new circuit.Figure10S",
                f"edit vsource.source basekv=11 pu={cfg['source_pu']} isc3={cfg['source_isc3_a']} isc1={cfg['source_isc1_a']}",
                f'redirect "{FEEDER / "LineCode.txt"}"', f'redirect "{FEEDER / "Lines.txt"}"',
                f"new transformer.tr1 buses=[SourceBus 1] conns=[delta wye] kvs=[11 .416] "
                f"kvas=[{cfg['transformer_kva']} {cfg['transformer_kva']}] xhl={cfg['transformer_xhl_percent']} "
                f"%rs=[{cfg['transformer_winding_r_percent']} {cfg['transformer_winding_r_percent']}] %noloadloss=0 %imag=0"]:
        dss.Text.Command(cmd)
    for r in mp.itertuples():
        dss.Text.Command(f"new load.{r.LoadName} phases=1 bus1={r.Bus}.{r.Phase} conn=wye kv=0.23 "
                         "kw=0 kvar=0 model=1 vminpu=0.5 vmaxpu=1.5")
    dss.Text.Command("set voltagebases=[11 .416]")
    dss.Text.Command("calcvoltagebases")
    dss.Text.Command("set mode=snapshot controlmode=off maxiterations=100 tolerance=0.00000001")
    assert dss.Loads.Count() == 55


def vuf_from_phasors(abc):
    a = np.exp(2j * np.pi / 3)
    positive = (abc[0] + a*abc[1] + a*a*abc[2]) / 3
    negative = (abc[0] + a*a*abc[1] + a*abc[2]) / 3
    if abs(positive) < 1e-6: raise ValueError("positive sequence voltage is zero")
    return float(100 * abs(negative) / abs(positive))


def power_flow(net, gross_load, mp, cfg):
    compile_feeder(cfg, mp)
    node_rows, time_rows = [], []
    q = gross_load * np.tan(np.arccos(cfg["load_power_factor"]))
    for t in range(len(net)):
        for n, row in enumerate(mp.itertuples()):
            dss.Loads.Name(row.LoadName); dss.Loads.kW(float(net[t,n])); dss.Loads.kvar(float(q[t,n]))
        dss.Solution.Solve()
        if not dss.Solution.Converged(): raise RuntimeError(f"Power flow failed at hour {t}")
        psource, qsource = -np.asarray(dss.Circuit.TotalPower())
        losses = np.asarray(dss.Circuit.Losses()) / 1000
        residual = abs(psource - net[t].sum() - losses[0])
        assert residual < 1e-3, (t, residual)
        seq_error = 0.0
        for row in mp.itertuples():
            dss.Circuit.SetActiveBus(row.Bus)
            nodes = dss.Bus.Nodes(); v = np.asarray(dss.Bus.Voltages()).reshape(-1,2)
            volts = {node: complex(*z) for node,z in zip(nodes,v)}
            assert {1,2,3}.issubset(volts), (row.Bus, nodes)
            abc = np.array([volts[k] for k in [1,2,3]])
            vuf = vuf_from_phasors(abc)
            seq = dss.Bus.SeqVoltages(); seq_error = max(seq_error, abs(vuf - 100*seq[2]/seq[1]))
            pu = abs(abc) / (dss.Bus.kVBase() * 1000)
            nr = {"Hour": t, "Customer": row.Customer, "Bus": row.Bus, "ConnectedPhase": row.Phase,
                  "ConnectedVoltagePU": float(pu[row.Phase-1]), "VUFPercent": vuf}
            for k, phase in enumerate("ABC"):
                nr[f"V{phase}RealV"] = float(abc[k].real); nr[f"V{phase}ImagV"] = float(abc[k].imag)
                nr[f"V{phase}PU"] = float(pu[k])
            node_rows.append(nr)
        assert seq_error < 1e-8, seq_error
        dss.Circuit.SetActiveElement("Transformer.tr1")
        s = np.asarray(dss.CktElement.Powers()).reshape(dss.CktElement.NumTerminals(),dss.CktElement.NumConductors(),2)
        kva = np.linalg.norm(s[0].sum(axis=0))
        line_loss = 0.0
        for name in dss.Lines.AllNames():
            dss.Circuit.SetActiveElement(f"Line.{name}"); line_loss += dss.CktElement.Losses()[0]/1000
        time_rows.append({"Hour": t, "SourceImportKW": float(psource), "SourceKvar": float(qsource),
                          "NetCustomerKW": float(net[t].sum()), "LossKW": float(losses[0]),
                          "LineLossKW": float(line_loss), "TransformerKVA": float(kva),
                          "TransformerLoadingPercent": float(100*kva/cfg["transformer_kva"]),
                          "BalanceResidualKW": float(residual), "VUFSequenceDifference": float(seq_error),
                          "Converged": True, "Iterations": dss.Solution.Iterations()})
    return pd.DataFrame(node_rows), pd.DataFrame(time_rows)


def validate_engine(cfg):
    # Known balanced phasors, then a physically unbalanced three-phase circuit.
    a = np.exp(2j*np.pi/3)
    assert vuf_from_phasors(np.array([230,230*a*a,230*a])) < 1e-10
    assert vuf_from_phasors(np.array([230,210*a*a,230*a])) > 2
    dss.Basic.ClearAll()
    for cmd in ["new circuit.validation basekv=0.416 pu=1 phases=3", "new line.l bus1=sourcebus bus2=b phases=3 r1=.2 x1=.05 r0=.4 x0=.1 length=1 units=km",
                "new load.a bus1=b.1 phases=1 kv=.2401777 kw=2 kvar=.5 model=1",
                "new load.b bus1=b.2 phases=1 kv=.2401777 kw=2 kvar=.5 model=1",
                "new load.c bus1=b.3 phases=1 kv=.2401777 kw=2 kvar=.5 model=1", "set tolerance=1e-10", "solve"]:
        dss.Text.Command(cmd)
    dss.Circuit.SetActiveBus("b"); sv = dss.Bus.SeqVoltages(); balanced = 100*sv[2]/sv[1]
    dss.Text.Command("edit load.a kw=6"); dss.Solution.Solve(); dss.Circuit.SetActiveBus("b")
    sv = dss.Bus.SeqVoltages(); unbalanced = 100*sv[2]/sv[1]
    assert balanced < 1e-6 and unbalanced > balanced + .1
    tariff = np.full(24,.2); tariff[:8] = .1
    c, d, e, metrics = optimise(np.full((24,1),1.0), np.zeros((24,1)), tariff, cfg)
    assert (c[:8].sum() > 0) and (d[8:].sum() > 0) and abs(e[0,0]-e[-1,0]) < 1e-8
    assert metrics["BillEUR"] < float(tariff.sum())
    return {"BalancedCircuitVUFPercent": balanced, "UnbalancedCircuitVUFPercent": unbalanced,
            "KnownBatteryArbitrageCheck": "pass"}


def configure_fonts():
    names = {f.name for f in font_manager.fontManager.ttflist}
    selected = next((n for n in ["PingFang TC", "Microsoft JhengHei", "Microsoft YaHei", "Heiti TC", "Arial Unicode MS", "Noto Sans CJK TC"] if n in names), "DejaVu Sans")
    plt.rcParams.update({"font.family": selected, "font.size": 10, "axes.unicode_minus": False,
                         "figure.facecolor": "white", "axes.spines.top": False, "axes.spines.right": False})


def plots(out, nodes, times, dates):
    configure_fonts()
    zmax = max(.01, nodes.VUFPercent.max()*1.05)
    fig = plt.figure(figsize=(13,5.6))
    for i,(season,case,title) in enumerate([("winter","POOL_FLAT","冬日（固定電價）"),
                                           ("summer","POOL_TOU","夏日（日夜電價）")],1):
        block = nodes[(nodes.Season==season)&(nodes.Case==case)].pivot(index="Customer",columns="Hour",values="VUFPercent")
        ax=fig.add_subplot(1,2,i,projection="3d")
        x,y=np.meshgrid(block.columns,block.index)
        surf=ax.plot_surface(x,y,block.to_numpy(),cmap="viridis",vmin=0,vmax=zmax,linewidth=.2,edgecolor="#ffffff40",rstride=1,cstride=1)
        ax.set(xlabel="小時（區間起點）",ylabel="客戶編號",zlabel="VUF (%)",zlim=(0,zmax),
               title=f"{title}\n{dates[season]}",xticks=[0,6,12,18,23],yticks=[1,10,20,30,40,55],ylim=(1,55))
        ax.view_init(elev=25,azim=-130)
    fig.suptitle("類似 Fig. 10 的模擬：冬、夏日電壓不平衡",fontsize=16)
    fig.text(.5,.025,"獨立模擬，非原論文逐點復現。55 個客戶由公開曲線循環配置；兩圖共用相同刻度。",ha="center",fontsize=10)
    fig.subplots_adjust(left=.01,right=.98,top=.82,bottom=.13,wspace=.04)
    fig.savefig(out/"圖10_電壓不平衡模擬.png",dpi=180);plt.close(fig)


def summary_row(nodes,times,metrics,case,season,date,cfg):
    return {"Season":season,"Date":date,"Case":case,"CaseChinese":LABELS[case],
            "MinVoltagePU":float(nodes.ConnectedVoltagePU.min()),"MaxVoltagePU":float(nodes.ConnectedVoltagePU.max()),
            "MaxVUFPercent":float(nodes.VUFPercent.max()),"MeanVUFPercent":float(nodes.VUFPercent.mean()),
            "CustomerHoursBelow095":int((nodes.ConnectedVoltagePU<cfg['voltage_reference_low_pu']).sum()),
            "CustomerHoursAbove105":int((nodes.ConnectedVoltagePU>cfg['voltage_reference_high_pu']).sum()),
            "CustomerHoursVUFAbove2":int((nodes.VUFPercent>cfg['vuf_reference_percent']).sum()),
            "PeakSourceImportKW":float(times.SourceImportKW.max()),"PeakReverseKW":float(max(0,-times.SourceImportKW.min())),
            "DailyLossKWh":float(times.LossKW.sum()),"DailyLineLossKWh":float(times.LineLossKW.sum()),
            "MaxTransformerLoadingPercent":float(times.TransformerLoadingPercent.max()),
            "MaxBalanceResidualKW":float(times.BalanceResidualKW.max()),"AllConverged":bool(times.Converged.all()),**metrics}


def write_note(out, summary, dates):
    winter=summary.iloc[0]; summer=summary.iloc[1]
    note=f"""# 圖 10：電壓不平衡模擬（簡單版）

打開「圖10_電壓不平衡模擬.png」即可看結果。

| 情境 | 日期 | 最高 VUF | 最低住戶電壓 |
|---|---|---:|---:|
| 冬日、固定電價 | {dates['winter']} | {winter.MaxVUFPercent:.3f}% | {winter.MinVoltagePU:.4f} p.u. |
| 夏日、日夜電價 | {dates['summer']} | {summer.MaxVUFPercent:.3f}% | {summer.MinVoltagePU:.4f} p.u. |

VUF 越大，代表三相電壓越不平衡。曲面上的每個點是一個客戶位置在某小時的 VUF。

這是類似論文 Fig. 10 的獨立模擬，不是原圖逐點復現。兩張圖同時改變季節和電價，不能單憑兩圖就把差異歸因於電價。

程式使用公開 IEEE 歐洲低壓饋線，把 StoreNet 的 20 戶用電、10 戶太陽能曲線循環配到 55 個客戶位置。每戶配置 10 kWh / 3.3 kW 電池，先求社區最低買電成本，再用 OpenDSS 算三相電壓。VUF = 負序電壓 / 正序電壓 × 100%。

冬日選一月完整資料中用電最高日；夏日選六月太陽能發電最高日。每小時必須有 60 筆有限、非負的發布資料，但發布值含原作者插值。H4 沿用發布時間，沒有自行校正。

電池電量 2–10 kWh、起訖 2 kWh、充放電效率各 95%。固定電價 0.2007 €/kWh；日夜電價 00–08 時為 0.0991，其餘 0.2007；售電 0.09。這些是來源研究情境，不是現行電價。

350 kVA 容量參照研究，線路等仍用公開基線；每側變壓器電阻 0.2%、電抗 4%、電源 1.05 p.u.。負載功率因數設 0.95，太陽能／電池設 1。55 戶映射、無損社區共同排程及最低成本同分擇解都是本版假設；未取得作者修改版電網、雙邊 P2P 模型或原始電壓矩陣。未建模顯式中性線，不能推論中性線對地電壓。每小時平均不能代替分鐘尖峰。

重跑：依 [Mac／Windows 操作說明](../../../02_中文程式導覽/01_Mac與Windows操作.md#data-figures) 執行圖 10。完成後到 `StoreNet/results/figure10_grid/` 開啟「圖10_電壓不平衡模擬.png」。

來源：[資料論文](https://doi.org/10.1038/s41597-024-03454-2)、[Saif 網路研究](https://doi.org/10.1016/j.egyr.2023.05.005)、[作者公開預印本](https://www.researchgate.net/publication/368317517)、[IEEE 饋線資料](https://github.com/ieee-pes-amps/dtf-dev/tree/master/European%20LV%20Test%20Feeder)、[OpenDSS 饋線程式](https://github.com/tshort/OpenDSS/tree/master/Distrib/IEEETestCases/LVTestCase)。

資料表、模擬設定和執行紀錄供需要核對時使用，平常看圖即可。
"""
    (out/"00_結果說明.md").write_text(note, encoding="utf-8")


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output",type=Path,default=ROOT/"results/figure10_grid")
    args=parser.parse_args();out=args.output.resolve();out.mkdir(parents=True,exist_ok=True)
    cfg=json.loads(CONFIG.read_text(encoding="utf-8")); (out/"模擬設定.json").write_text(json.dumps(cfg,ensure_ascii=False,indent=2), encoding="utf-8")
    validation=verify_feeder_inputs();validation.update(validate_engine(cfg))
    log("已通過公開饋線、三相平衡／不平衡及電池能量檢查。")
    profiles,dates,hashes=load_profiles(out);log(f"代表日：冬 {dates['winter']}；夏 {dates['summer']}")
    mp=mapping();mp.to_csv(out/"55戶與電網節點映射.csv",index=False,encoding="utf-8-sig")
    all_nodes=[];all_times=[];summaries=[];dispatch=[]
    for season,date in dates.items():
        case="POOL_FLAT" if season=="winter" else "POOL_TOU"
        load,pv=day_arrays(profiles,date,mp)
        log(f"計算 {date}：{LABELS[case]}")
        c,d,e,metrics,tariff=schedule(load,pv,case,cfg)
        nodes,times=power_flow(load-pv+c-d,load,mp,cfg)
        for frame in [nodes,times]:frame["Season"]=season;frame["Date"]=date;frame["Case"]=case
        all_nodes.append(nodes);all_times.append(times)
        summaries.append(summary_row(nodes,times,metrics,case,season,date,cfg))
        for t in range(24):
            for n in range(55):
                dispatch.append({"Season":season,"Date":date,"Case":case,"Hour":t,"Customer":n+1,
                                 "LoadKW":load[t,n],"PVKW":pv[t,n],"ChargeKW":c[t,n],"DischargeKW":d[t,n],
                                 "StartEnergyKWh":e[t,n],"EndEnergyKWh":e[t+1,n],"NetImportKW":load[t,n]-pv[t,n]+c[t,n]-d[t,n],
                                 "BuyEURPerKWh":tariff[t]})
    nodes=pd.concat(all_nodes,ignore_index=True);times=pd.concat(all_times,ignore_index=True);summary=pd.DataFrame(summaries)
    for frame,name in [(nodes,"三相電壓與VUF.csv"),(times,"電網功率與損失.csv"),
                       (summary,"結果摘要.csv"),(pd.DataFrame(dispatch),"電池排程.csv")]:
        frame.to_csv(out/name,index=False,encoding="utf-8-sig")
    validation.update({"PowerFlows":len(times),"AllConverged":bool(times.Converged.all()),
                       "MaxPowerBalanceResidualKW":float(times.BalanceResidualKW.max()),
                       "MaxVUFSequenceDifference":float(times.VUFSequenceDifference.max()),
                       "MaxLPResidual":float(summary.LPResidual.max()),
                       "MaxSimultaneousChargeDischargeKW":float(summary.SimultaneousChargeDischargeKW.max())})
    (out/"驗證結果.json").write_text(json.dumps(validation,ensure_ascii=False,indent=2), encoding="utf-8")
    log("輸出一張中文 VUF 圖與簡短說明。")
    plots(out,nodes,times,dates);write_note(out,summary,dates)
    manifest={"classification":cfg['classification'],"dates":dates,"source_inputs_sha256":hashes,
              "code_sha256":sha(Path(__file__)),"config_sha256":sha(CONFIG),
              "python":sys.version,"engine":dss.Basic.Version(),
              "packages":{p:importlib.metadata.version(p) for p in ["OpenDSSDirect.py","dss-python","dss-python-backend","scipy","numpy","pandas","matplotlib"]},
              "feeder_provenance":json.loads((FEEDER/"來源紀錄.json").read_text(encoding="utf-8")),
              "outputs_sha256":{p.name:sha(p) for p in sorted(out.iterdir()) if p.is_file() and p.name!="來源與執行紀錄.json"}}
    (out/"來源與執行紀錄.json").write_text(json.dumps(manifest,ensure_ascii=False,indent=2), encoding="utf-8")
    log(f"完成：{out/'圖10_電壓不平衡模擬.png'}")


if __name__=="__main__":
    main()
