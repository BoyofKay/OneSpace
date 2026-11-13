/// Android root-route back handling: only a deliberate second back gesture
/// within the confirmation interval is allowed to exit. Other navigation
/// resets the pending confirmation.
class BackExitPolicy {
 BackExitPolicy({this.window=const Duration(seconds:2)});
 final Duration window;
 DateTime? _firstBack;
 bool shouldExit(DateTime time){
   final previous=_firstBack;
   if(previous!=null){
     final elapsed=time.difference(previous);
     if(!elapsed.isNegative && elapsed<=window){
       _firstBack=null;
       return true;
     }
   }
   _firstBack=time;
   return false;
 }
 void reset()=>_firstBack=null;
}
