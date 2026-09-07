"""Physical and optimisation checks for the independent grid simulation."""
import json
from pathlib import Path
import sys
import unittest
import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'src'))
from simulate_figure10s_grid import CONFIG, mapping, optimise, power_flow, validate_engine, vuf_from_phasors


class Figure10SChecks(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.cfg=json.loads(CONFIG.read_text())

    def test_complex_voltage_not_magnitude_only(self):
        # Equal magnitudes with incorrect phase angles must still produce VUF.
        a=np.exp(2j*np.pi/3)
        balanced=np.array([240,240*a*a,240*a])
        self.assertLess(vuf_from_phasors(balanced),1e-10)
        shifted=balanced.copy();shifted[1]*=np.exp(1j*.1)
        self.assertGreater(vuf_from_phasors(shifted),1)

    def test_flat_tariff_no_pv_no_free_energy(self):
        load=np.ones((24,1));pv=np.zeros_like(load)
        c,d,e,m=optimise(load,pv,np.full(24,.2),self.cfg)
        self.assertLess(c.sum()+d.sum(),1e-5)
        self.assertAlmostEqual(m['BillEUR'],4.8,places=6)
        np.testing.assert_allclose(e,2,atol=1e-6)

    def test_mapping_has_55_valid_connections(self):
        frame=mapping()
        self.assertEqual(len(frame),55)
        self.assertEqual(set(frame.Phase),{1,2,3})
        self.assertTrue(frame.LoadHouse.between(1,20).all())
        self.assertTrue(frame.PVHouse.between(1,10).all())

    def test_engine_balance_and_export(self):
        validate_engine(self.cfg)
        # Unity-power-factor net generators cause reverse flow and positive losses.
        cfg=dict(self.cfg);cfg['load_power_factor']=1
        nodes,times=power_flow(np.full((1,55),-1.),np.zeros((1,55)),mapping(),cfg)
        self.assertLess(times.SourceImportKW.iloc[0],0)
        self.assertGreater(times.LossKW.iloc[0],0)
        self.assertLess(times.BalanceResidualKW.max(),1e-3)
        self.assertEqual(len(nodes),55)


if __name__=='__main__':
    unittest.main()
