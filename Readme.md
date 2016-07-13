## LProf v0.1.0, by Joel Self 2016. MIT Licence http://www.opensource.org/licenses/mit-license.php.
Based on [ProFi v1.3](https://gist.github.com/perky/2838755), by Luke Perkin 2012. MIT Licence http://www.opensource.org/licenses/mit-license.php. But actually maintained and improved.

#### Note, this is baby's first lua project, I've literally never written or modified lua code until now.

## Example:
  ```lua
    LProf = require 'LProf'
    LProf:start()
    some_function()
    another_function()
    coroutine.resume( some_coroutine )
    LProf:stop()
    LProf:writeReport( 'MyProfilingReport.txt' )
  ```

## API:

  Arguments are specified as: type/name/default.

      LProf:start( string/once/nil )
      LProf:stop()
      LProf:checkMemory( number/interval/0, string/note/'' )
      LProf:writeReport( string/filename/'LProf.txt' )
      LProf:reset()
      LProf:setHookCount( number/hookCount/0 )
      LProf:setGetTimeMethod( function/getTimeMethod/os.clock )
      LProf:setInspect( string/methodName, number/levels/1 )
