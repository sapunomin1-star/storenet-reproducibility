import numpy as np, pandas as pd
d = np.load("data/prep/storenet_30min.npz")
t = pd.to_datetime(d['t'], unit='s'); load=d['load']; pv=d['pv']; imp=d['imp']; exp=d['exp']
dt = 0.5
tar = np.where((t.hour>=10)&(t.hour<22), 0.194, 0.091)          # EUR/kWh
hasPV = pv.sum(0) > 50
print("PV houses:", [i+1 for i in np.where(hasPV)[0]], "->", hasPV.sum(), "戶")
print(f"年總負載 {load.sum()/1000:8.1f} MWh   年總 PV {pv.sum()/1000:7.1f} MWh  ({pv.sum()/load.sum()*100:.1f}% of load)")

base = (tar*load.sum(1)).sum()
print(f"\n[Baseline] 無 PV 無電池 年電費  EUR {base:,.0f}")

selfc_house = np.minimum(load, pv).sum(1)                        # 各戶自用（不共享）
selfc_vpp   = np.minimum(load.sum(1), pv.sum(1))                 # 社區共享（無損失上限）
for name, sc in [("PV 自用（單戶，不共享）", selfc_house), ("PV 自用（VPP 共享，ξ=0 上限）", selfc_vpp)]:
    bill = (tar*(load.sum(1)-sc)).sum()
    print(f"  {name:<28} 省 {100*(1-bill/base):5.2f}%   (EUR {bill:,.0f})")

sbsc = (tar*imp.sum(1)).sum()
print(f"  {'SB-SC（實測 From grid）':<28} 省 {100*(1-sbsc/base):5.2f}%   (EUR {sbsc:,.0f})")
print(f"  {'  其中饋網 (Feed-in) 年量':<28} {exp.sum()/1000:.2f} MWh  ← 零饋網假設的檢驗")

agg = pd.DataFrame({'load':load.sum(1), 'pv':pv.sum(1), 'imp':imp.sum(1)}, index=t)
day = agg.resample('D').agg(load=('load','sum'), pv=('pv','sum'), pk=('load','max'))
day['pk_kW'] = day['pk']/dt
print(f"\n全年 20 戶合計負載尖峰 (30min 平均功率):  中位 {day.pk_kW.median():.1f} kW   最大 {day.pk_kW.max():.1f} kW")
cand = day[(day.pk_kW.between(18,23)) & (day.pv>day.pv.quantile(.6))].sort_values('pv',ascending=False)
print(f"\n『典型日』候選（合計尖峰 18–23 kW 且 PV 發電量在前 40%）共 {len(cand)} 天，前 10:")
print((cand[['load','pv','pk_kW']].head(10)).round(1).to_string())
