"""Guard actual fallback/ownership and stale-report failures without changing App files."""
import importlib.util,json,tempfile,unittest
from pathlib import Path
from unittest.mock import patch
spec=importlib.util.spec_from_file_location('ledger',Path(__file__).resolve().parents[1]/'exercise_media_ledger.py');ledger=importlib.util.module_from_spec(spec);spec.loader.exec_module(ledger)
class MediaLedgerTests(unittest.TestCase):
 def test_youtube_parsing_rejects_spoofed_hosts(self):
  self.assertEqual(ledger.youtube('https://youtu.be/6LrMOI0VN3I'),'6LrMOI0VN3I')
  self.assertEqual(ledger.youtube('https://www.youtube.com/shorts/6LrMOI0VN3I'),'6LrMOI0VN3I')
  self.assertIsNone(ledger.youtube('https://youtube.com.evil.test/watch?v=6LrMOI0VN3I'))
  self.assertIsNone(ledger.youtube('javascript:alert(1)'))
 def test_current_adoption_precedes_old_picture(self):
  d,_=ledger.build();by={r['id']:r for r in d['rows']};r=by['push_up']
  self.assertEqual(r['defaultMedia']['type'],'adopted_video')
  self.assertEqual(r['listCover']['type'],'bundled_cover')
  self.assertEqual(by['cable_crossover_mid']['defaultMedia']['type'],'adopted_video')
 def test_revocation_is_a_hard_failure(self):
  original=ledger.read;digest=original(ledger.INPUTS[2])[0]['sha256']
  with patch.object(ledger,'read',side_effect=lambda p:[digest] if p==ledger.INPUTS[3] else original(p)):
   with self.assertRaisesRegex(AssertionError,'Revoked'):ledger.build()
 def test_missing_queue_never_regenerates_adopted_video(self):
  d,_=ledger.build();queue=[r for r in d['rows'] if r['productionReview']['missingVideo']]
  self.assertTrue(all((not r['video'] or (r.get('origin') or {}).get('originalFormat')=='still') and r['productionReview']['task']=='generate_video' for r in queue))
  self.assertEqual(sorted(r['productionReview']['rank'] for r in queue),list(range(1,len(queue)+1)))
  self.assertTrue(all(r['productionReview']['rank'] is None for r in d['rows'] if r['video'] and (r.get('origin') or {}).get('originalFormat')!='still'))
  self.assertEqual(next(r for r in queue if r['id']=='wall_sit')['origin']['originalFormat'],'still')
 def test_changed_cover_invalidates_old_review(self):
  d,_=ledger.build();r=next(r for r in d['rows'] if r['productionReview']['coverFlagged'])
  import copy
  r=copy.deepcopy(r);old=r['listCover']['urls'];r['listCover']['urls']=['https://example.test/new-cover.jpg']
  ledger.production_review([r],{'date':'2026-10-23','findings':[{'exerciseId':r['id'],'coverBinding':old,'videoSHA256':r['video']['sha256'] if r['video'] else None,'codes':['critical_equipment_cropped'],'note':'Old cover issue'}]})
  self.assertTrue(r['productionReview']['staleReview']);self.assertFalse(r['productionReview']['coverFlagged']);self.assertIsNone(r['productionReview']['note'])
 def test_obvious_wrong_legacy_aliases_use_own_fallback(self):
  d,_=ledger.build();by={r['id']:r for r in d['rows']}
  for id in ['belt_squat','shoulder_stretch_sleeper','prone_t_raise','pull_up_l_sit','rowing_machine_sprint','supported_dumbbell_row_machine']:
   self.assertNotEqual(by[id]['defaultMedia']['type'],'legacy_frames')
 def test_saved_exports_detect_source_changes(self):
  with tempfile.TemporaryDirectory() as tmp:
   out=Path(tmp);(out/'template.html').write_text((ledger.OUT/'template.html').read_text())
   with patch.object(ledger,'OUT',out):
    ledger.export();ledger.export(check=True)
    original=ledger.read
    def changed(p):
     data=original(p)
     if p==ledger.INPUTS[0]:data[0]['name']['en']='Updated action title'
     return data
    with patch.object(ledger,'read',side_effect=changed):
     with self.assertRaisesRegex(ValueError,'Ledger stale'):ledger.export(check=True)
if __name__=='__main__':unittest.main()
