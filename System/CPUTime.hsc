-----------------------------------------------------------------------------
-- 
-- Module      :  System.CPUTime
-- Copyright   :  (c) The University of Glasgow 2001
-- License     :  BSD-style (see the file libraries/core/LICENSE)
-- 
-- Maintainer  :  libraries@haskell.org
-- Stability   :  provisional
-- Portability :  portable
--
-- $Id: CPUTime.hsc,v 1.3 2001/07/31 12:50:18 simonmar Exp $
--
-- The standard CPUTime library.
--
-----------------------------------------------------------------------------

module System.CPUTime 
	(
         getCPUTime,       -- :: IO Integer
	 cpuTimePrecision  -- :: Integer
        ) where

import Prelude

import Foreign
import Foreign.C

import Data.Ratio

#include "HsCore.h"

-- -----------------------------------------------------------------------------
-- Computation `getCPUTime' returns the number of picoseconds CPU time
-- used by the current program.  The precision of this result is
-- implementation-dependent.

-- The `cpuTimePrecision' constant is the smallest measurable difference
-- in CPU time that the implementation can record, and is given as an
-- integral number of picoseconds.

getCPUTime :: IO Integer
getCPUTime = do

#if !defined(mingw32_TARGET_OS) && !defined(cygwin32_TARGET_OS)
-- getrusage() is right royal pain to deal with when targetting multiple
-- versions of Solaris, since some versions supply it in libc (2.3 and 2.5),
-- while 2.4 has got it in libucb (I wouldn't be too surprised if it was back
-- again in libucb in 2.6..)
--
-- Avoid the problem by resorting to times() instead.
--
#if defined(HAVE_GETRUSAGE) && ! irix_TARGET_OS && ! solaris2_TARGET_OS
    allocaBytes (#const sizeof(struct rusage)) $ \ p_rusage -> do
    getrusage (#const RUSAGE_SELF) p_rusage

    let ru_utime = (#ptr struct rusage, ru_utime) p_rusage
    let ru_stime = (#ptr struct rusage, ru_stime) p_rusage
    u_sec  <- (#peek struct timeval,tv_sec)  ru_utime :: IO CLong
    u_usec <- (#peek struct timeval,tv_usec) ru_utime :: IO CLong
    s_sec  <- (#peek struct timeval,tv_sec)  ru_stime :: IO CLong
    s_usec <- (#peek struct timeval,tv_usec) ru_stime :: IO CLong

    return ((fromIntegral u_sec * 1000000 + fromIntegral u_usec + 
             fromIntegral s_sec * 1000000 + fromIntegral s_usec) 
		* 1000000)

type CRUsage = ()
foreign import unsafe getrusage :: CInt -> Ptr CRUsage -> IO CInt
#else
# if defined(HAVE_TIMES)
    allocaBytes (#const sizeof(struct tms)) $ \ p_tms -> do
    times p_tms
    u_ticks  <- (#peek struct tms,tms_utime) p_tms :: IO CClock
    s_ticks  <- (#peek struct tms,tms_stime) p_tms :: IO CClock
    return (( (fromIntegral u_ticks + fromIntegral s_ticks) * 1000000000000) 
			`div` clockTicks)

type CTms = ()
foreign import unsafe times :: Ptr CTms -> CClock
# else
    ioException (IOError Nothing UnsupportedOperation 
			 "getCPUTime"
		         "can't get CPU time"
			 Nothing)
# endif
#endif

#else /* win32 */
    allocaBytes (#const sizeof(FILETIME)) $ \ p_creationTime -> do
    allocaBytes (#const sizeof(FILETIME)) $ \ p_exitTime -> do
    allocaBytes (#const sizeof(FILETIME)) $ \ p_kernelTime -> do
    allocaBytes (#const sizeof(FILETIME)) $ \ p_userTime -> do
    pid <- getCurrentProcess
    ok <- getProcessTimes pid p_creationTime p_exitTime p_kernelTime p_userTime
    if toBool ok then do
      ut <- ft2psecs p_userTime
      kt <- ft2psecs p_kernelTime
      return (fromIntegral (ut + kt))
     else return 0
  where ft2psecs ft = do
          high <- (#peek FILETIME,dwHighDateTime) ft :: IO CLong
          low <- (#peek FILETIME,dwLowDateTime) ft :: IO CLong
          return (((fromIntegral high) * (2^32) + (fromIntegral low)) * 100000)

    -- ToDo: pin down elapsed times to just the OS thread(s) that
    -- are evaluating/managing Haskell code.

type FILETIME = ()
type HANDLE = ()
-- need proper Haskell names (initial lower-case character)
foreign import "GetCurrentProcess" unsafe getCurrentProcess :: IO (Ptr HANDLE)
foreign import "GetProcessTimes" unsafe getProcessTimes :: Ptr HANDLE -> Ptr FILETIME -> Ptr FILETIME -> Ptr FILETIME -> Ptr FILETIME -> IO CInt

#endif /* not _WIN32 */

cpuTimePrecision :: Integer
cpuTimePrecision = round ((1000000000000::Integer) % fromIntegral (clockTicks))

clockTicks :: Int
clockTicks =
#if defined(CLK_TCK)
    (#const CLK_TCK)
#else
    unsafePerformIO (sysconf (#const _SC_CLK_TCK) >>= return . fromIntegral)
foreign import unsafe sysconf :: CInt -> IO CLong
#endif
