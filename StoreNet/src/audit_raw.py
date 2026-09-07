import sys, pandas as pd, numpy as np
RAW = sys.argv[1]; hs = [int(x) for x in sys.argv[2].split(',')]
COLS = ['date','Discharge(Wh)','Charge(Wh)','Production(Wh)','Consumption(Wh)',
        'Feed-in(Wh)','From grid(Wh)','State of Charge(%)']
print(f"{'H':>4} {'rows':>7} {'load_kWh':>9} {'pv_kWh':>8} {'imp_kWh':>8} {'exp_kWh':>8} "
      f"{'ch_kWh':>7} {'dis_kWh':>7} {'bal_max':>8} {'PV?':>4} {'t0':>16} {'t1':>16}")
for h in hs:
    df = pd.read_csv(f"{RAW}/H{h}_Wh.csv", skipinitialspace=True)
    df.columns = [c.strip() for c in df.columns]
    d = pd.to_datetime(df['date'])
    bal = (df['From grid(Wh)'] + df['Production(Wh)'] + df['Discharge(Wh)']
           - df['Consumption(Wh)'] - df['Charge(Wh)'] - df['Feed-in(Wh)'])
    pv = df['Production(Wh)'].sum()/1000
    print(f"{h:>4} {len(df):>7} {df['Consumption(Wh)'].sum()/1000:>9.1f} {pv:>8.1f} "
          f"{df['From grid(Wh)'].sum()/1000:>8.1f} {df['Feed-in(Wh)'].sum()/1000:>8.1f} "
          f"{df['Charge(Wh)'].sum()/1000:>7.1f} {df['Discharge(Wh)'].sum()/1000:>7.1f} "
          f"{bal.abs().max():>8.2f} {'Y' if pv>50 else '-':>4} "
          f"{str(d.iloc[0])[5:16]:>16} {str(d.iloc[-1])[5:16]:>16}")
