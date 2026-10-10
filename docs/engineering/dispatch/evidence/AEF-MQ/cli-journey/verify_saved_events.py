import pathlib, json, datetime
EV=pathlib.Path(__file__).resolve().parent
def check():
 events=[json.loads(f.read_text()) for f in (EV/'events').glob('*.json')];s=json.loads((EV/'summary.json').read_text())
 def stamp(e):return datetime.datetime.fromisoformat(e['at']).timestamp()
 starts={};active=[];wait=[];effort=0
 for e in sorted(events,key=stamp):
  key=(e['task_id'],e['lane_id'],e['interval_id'])
  if e['type'] in ['active_start','wait_start']:starts[key]=e
  if e['type'] in ['active_stop','wait_stop']:
   a=starts.pop(key);pair=(stamp(a),stamp(e));(active if e['type']=='active_stop' else wait).append(pair)
   if e['type']=='active_stop':effort+=pair[1]-pair[0]
 def union(xs):
  total=0;end=None
  for a,b in sorted(xs):total+=max(0,b-max(a,end if end is not None else a));end=max(b,end if end is not None else b)
  return total
 elapsed=stamp(next(e for e in events if e['type']=='run_stop'))-stamp(next(e for e in events if e['type']=='run_start'))
 expected={'elapsed_seconds':elapsed,'active_union_seconds':union(active),'lane_effort_seconds':effort,'waiting_union_seconds':union(wait),'unknown_seconds':elapsed-union(active+wait)}
 for k,v in expected.items():assert abs(s[k]-v)<0.00001,(k,s[k],v)
 assert s['lane_effort_seconds']>s['active_union_seconds']
 assert s['observed_counts']['attempt']==1 and s['observed_counts']['correction']==1 and s['observed_counts']['test_failure']==1
 assert s['observed_outcomes']['human_qa']=={'fail':1} and s['observed_outcomes']['ai_verification']=={'pass':1}
 assert len([e for e in events if e['type']=='attempt'])==1
 assert len([e for e in events if e['type']=='ai_verification' and e['outcome']=='pass'])==1
 assert len([e for e in events if e['type']=='human_qa' and e['outcome']=='fail'])==1
 (EV/'calculation-check.json').write_text(json.dumps({'synthetic':True,'event_count':len(events),'independent_expected_seconds':expected,'result':'PASS'},indent=2)+'\n')
 print('independent event-derived duration/count check PASS')
if __name__=='__main__':check()
