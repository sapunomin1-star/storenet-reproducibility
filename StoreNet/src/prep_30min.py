import pandas as pd, numpy as np, os, sys
RAW = sys.argv[1]; OUT = sys.argv[2]; FREQ = sys.argv[3] if len(sys.argv)>3 else '30min'
os.makedirs(OUT, exist_ok=True)
CH = {'Discharge(Wh)':'dis','Charge(Wh)':'ch','Production(Wh)':'pv',
      'Consumption(Wh)':'load','Feed-in(Wh)':'exp','From grid(Wh)':'imp'}
res1, mats, socs = {}, {c:[] for c in CH.values()}, []
idx = pd.date_range('2020-01-01 00:00', '2021-01-01 00:00', freq=FREQ, inclusive='left')
for h in range(1,21):
    df = pd.read_csv(f"{RAW}/H{h}_Wh.csv", skipinitialspace=True)
    df.columns = [c.strip() for c in df.columns]
    df['date'] = pd.to_datetime(df['date']); df = df.set_index('date').sort_index()
    r = (df['From grid(Wh)']+df['Production(Wh)']+df['Discharge(Wh)']
         -df['Consumption(Wh)']-df['Charge(Wh)']-df['Feed-in(Wh)'])
    g = df[list(CH)].resample(FREQ).sum().reindex(idx).fillna(0.0)
    rr = (g['From grid(Wh)']+g['Production(Wh)']+g['Discharge(Wh)']
          -g['Consumption(Wh)']-g['Charge(Wh)']-g['Feed-in(Wh)'])
    res1[h] = (r.abs().mean(), r.abs().quantile(.999), r.abs().max(),
               rr.abs().mean(), rr.abs().max(), g['Consumption(Wh)'].sum()/1000)
    for k,v in CH.items(): mats[v].append(g[k].values/1000.0)   # kWh per interval
    socs.append(df['State of Charge(%)'].resample(FREQ).last().reindex(idx).ffill().fillna(0).values)
M = {k: np.column_stack(v) for k,v in mats.items()}; M['soc'] = np.column_stack(socs)
np.savez_compressed(f"{OUT}/storenet_{FREQ}.npz", t=idx.values.astype('datetime64[s]').astype(np.int64), **M)
print(f"saved {OUT}/storenet_{FREQ}.npz  shape={M['load'].shape}  (kWh per {FREQ} interval)")
print(f"\n{'H':>3} {'|res|_1min_mean':>16} {'p99.9':>8} {'max':>7} | {'|res|_'+FREQ+'_mean':>16} {'max':>8}")
for h,(a,b,c,d,e,_) in res1.items():
    print(f"{h:>3} {a:>16.3f} {b:>8.2f} {c:>7.2f} | {d:>16.3f} {e:>8.2f}")
