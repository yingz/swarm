/*! \file euler.cu
 * \brief declares prop_euler & factory 
 */

#include <limits>
#include "swarm.h"
#include "euler.h"
#include "swarmlog.h"
#include "../src/stopper.cu"

/*

	\brief gpu_generic_integrator - Versatile GPU integrator template

	gpu_generic_integrator is a template class designed to make it easy to implement
	powerful GPU-based integrators by supplying a 'propagator' class (that provides
	a function to advance the ensemble by one timestep), and a 'stopper' class (that
	tests whether the integration should stop for a particular system in the
	ensemble). Given the two classes, gpu_generic_integrator acts as a driver
	routine repeatedly calling the GPU kernel until all systems in the ensemble have
	finished the integration. It does this in an optimized manner, taking care to
	compactify() the ensemble when needed to efficiently utilize GPU resources
	(NOTE: compactification not yet implemented).

	For a cannonical example of how to build an integrator using
	gpu_generic_integrator, look at the gpu_euler integrator.

	Integration loop outline (I == gpu_generic_integrator object, H == propagator
	object, stop == stopper object):

	I.integrate(ens):
		if(ens.last_integrator() != this):
			H.initialize(ens);
			stop.initialize(ens);
		do:
			gpu_integrate<<<>>>(max_step, ens, (gpu_t)H, (gpu_t)stop)	[m'threaded execution on the GPU]
				while step < max_step:
					if(T < Tend || stop()):
						ens(sys).flags |= INACTIVE
						break;
					H.advance():			[ implementation supplied by the developer ]
						foreach(bod in sys):
							advance bod
							call stop.test_body
						return new time T
			if(beneficial):
				ens.compactify();
		while(active_systems > 0)

	To build an integrator using gpu_generic_integrator, the developer must supply a
	propagator and a stopper class that conform to the following interfaces:

	// propagator class: advance the system by one time step
	//
	// CPU state and interface. Will be instantiated on construction
	// of gpu_generic_integrator object. Keep any data that needs
	// to reside on the CPU here.
	struct propagator
	{
		// GPU state and interface (per-grid). Will be passed 
		// as an argument to integration kernel. Any per-block read-only
		// variables should be members of this structure.
		struct gpu_t
		{
			// GPU per-thread state and interface. Will be instantiated
			// in the integration kernel. Any per-thread
			// variables should be members of this structure.
			struct thread_state_t
			{
				__device__ thread_state_t(const gpu_t &H, ensemble &ens, const int sys, double T, double Tend);
			};

			// Advance the system - this function must advance the system
			// sys by one timestep, making sure that T does not exceed Tend.
			// Must return the new time of the system.
			//
			// This function MUST also call stop.test_body() for every body
			// in the system, after that body has been advanced by a timestep.
			template<typename stop_t>
			__device__ double advance(ensemble &ens, thread_state_t &pt, int sys, double T, double Tend, stop_t &stop, typename stop_t::thread_state_t &stop_ts, int step)
		};

		// Constructor will be passed the cfg object with the contents of
		// integrator configuration file. It will be called during construction
		// of gpu_generic_integrator. It should load any values necessary
		// for initialization.
		propagator(const config &cfg);

		// Initialize temporary variables for ensemble ens. This function
		// should initialize any temporary state that is needed for integration
		// of ens. It will be called from gpu_generic_integrator, but only
		// if ens.last_integrator() != this. If any temporary state exists from
		// previous invocation of this function, it should be deallocated and
		// the new state (re)allocated.
		void initialize(ensemble &ens);

		// Cast operator for gpu_t. This operator must return the gpu_t object
		// to be passed to integration kernel. It is called once per kernel
		// invocation.
		operator gpu_t();
	};


	// stopper class: mark a system inactive if conditions are met
	//
	// CPU state and interface. Will be instantiated on construction
	// of gpu_generic_integrator object. Keep any data that needs
	// to reside on the CPU here.
	struct stopper
	{
		// GPU state and interface (per-grid). Will be passed 
		// as an argument to integration kernel. Any per-block read-only
		// variables should be members of this structure.
		struct gpu_t
		{
			// GPU per-thread state and interface. Will be instantiated
			// in the integration kernel. Any per-thread
			// variables should be members of this structure.
			struct thread_state_t
			{
				__device__ thread_state_t(gpu_t &stop, ensemble &ens, const int sys, double T, double Tend);
			};

			// test any per-body stopping criteria for body (sys,bod). If 
			// your stopping criterion only depends on (x,v), test for it 
			// here. This will save you the unnecessary memory accesses 
			// that would otherwise be made if the test was made from 
			// operator().
			//
			// Called _after_ the body 'bod' has advanced a timestep.
			//
			// Note: you must internally store the result of your test,
			// and use/return it in subsequent call to operator().
			//
			__device__ void test_body(thread_state_t &ts, ensemble &ens, int sys, int bod, double T, double x, double y, double z, double vx, double vy, double vz);

			// Called after a system sys has been advanced by a timestep.
			// Must return true if the system sys is to be flagged as
			// INACTIVE (thus stopping further integration)
			__device__ bool operator ()(thread_state_t &ts, ensemble &ens, int sys, int step, double T);
		};

		// Constructor will be passed the cfg object with the contents of
		// integrator configuration file. It will be called during construction
		// of gpu_generic_integrator. It should load any values necessary
		// for initialization.
		stopper(const config &cfg);

		// Initialize temporary variables for ensemble ens. This function
		// should initialize any temporary state that is needed for integration
		// of ens. It will be called from gpu_generic_integrator, but only
		// if ens.last_integrator() != this. If any temporary state exists from
		// previous invocation of this function, it should be deallocated and
		// the new state (re)allocated.
		void initialize(ensemble &ens);

		// Cast operator for gpu_t. This operator must return the gpu_t object
		// to be passed to integration kernel. It is called once per kernel
		// invocation.
		operator gpu_t();
	};

*/

/// namespace for Swarm-NG library
namespace swarm {

/// propagator for Euler integration (do NOT use)
struct prop_euler
{
	/// GPU state and interface (per-grid) for prop_euler
	struct gpu_t
	{
		// any per-block variables 
		double h;
		cuxDevicePtr<double, 3> aa;

		/// GPU per-thread state and interface for prop_euler
		struct thread_state_t
		{
			__device__ thread_state_t(const gpu_t &H, ensemble &ens, const int sys, double T, double Tend)
			{ }
		};
		__host__ __device__ static int threads_per_system(int nbod) { return 1; }
 
		/// advances the system using euler propagator
		template<typename stop_t>
		__device__ double advance(ensemble &ens, thread_state_t &pt, int sys, int thr, double T, double Tend, stop_t &stop, typename stop_t::thread_state_t &stop_ts, int step)
		{
			if(T >= Tend) { return T; }
			double h = T + this->h <= Tend ? this->h : Tend - T;

			// compute accelerations
			compute_acc(ens, sys, aa);

			for(int bod = 1; bod != ens.nbod(); bod++) // starting from 1, assuming 0 is the central body
			{
				// load
				double  x = ens.x(sys, bod),   y = ens.y(sys, bod),   z = ens.z(sys, bod);
				double vx = ens.vx(sys, bod), vy = ens.vy(sys, bod), vz = ens.vz(sys, bod);

				// advance
				x += vx * h;
				y += vy * h;
				z += vz * h;
				vx += aa(sys, bod, 0) * h;
				vy += aa(sys, bod, 1) * h;
				vz += aa(sys, bod, 2) * h;

				stop.test_body(stop_ts, ens, sys, bod, T+h, x, y, z, vx, vy, vz);

				// store
				ens.x(sys, bod)  = x;   ens.y(sys, bod) = y;   ens.z(sys, bod) = z;
				ens.vx(sys, bod) = vx; ens.vy(sys, bod) = vy; ens.vz(sys, bod) = vz;
			}

			return T + h;
		}
	};

	// CPU state and interface
	cuxDeviceAutoPtr<double, 3> aa;
	gpu_t gpu_obj;

	/// initialize the euler propagator
	void initialize(ensemble &ens)
	{
		// Here you'd initialize the object to be passed to the kernel, or
		// upload any temporary data you need to constant/texture/global memory
		aa.realloc(ens.nsys(), ens.nbod(), 3);
		gpu_obj.aa = aa;
	}

	/// read in integrator parameters for the euler propagator
	prop_euler(const config &cfg)
	{
		if(!cfg.count("time step")) ERROR("Integrator gpu_euler requires a timestep ('time step' keyword in the config file).");
		gpu_obj.h = atof(cfg.at("time step").c_str());
	}

	/// return the gpu data for the euler propagator
	operator gpu_t()
	{
		return gpu_obj;
	}
};

#if 0
/// a simple stopper that checks if the distance from origin exceeds a threshold (for demonstration purposes only)
struct stop_on_ejection
{
	/// GPU state and interface (per-grid) for stop_on_ejection
	struct gpu_t
	{
		float rmax;

		/// GPU per-thread state and interface for stop_on_ejection
		struct thread_state_t
		{
			bool eject;

			__device__ thread_state_t(gpu_t &stop, ensemble &ens, const int sys, double T, double Tend)
			{
				eject = false;
			}
		};

		/// this is called _after_ the body 'bod' has advanced a timestep.
		__device__ void test_body(thread_state_t &ts, ensemble &ens, int sys, int bod, double T, double x, double y, double z, double vx, double vy, double vz)
		{
			float r = sqrtf(x*x + y*y + z*z);
			if(r < rmax) { return; }
//			::debug_hook();
			ts.eject = true;
//			lprintf(dlog, "Ejection detected: sys=%d, bod=%d, r=%f, T=%f.\n", sys, bod, r, T);
			log::event(dlog, swarm::log::EVT_EJECTION, T, sys, make_body_set(ens, sys, bod));
		}

		/// this is called after the entire system has completed a single timestep advance.
		__device__ bool operator ()(thread_state_t &ts, ensemble &ens, int sys, int step, double T) /// should be overridden by the user
		{
			if(ts.eject)
			{
				// store the last snapshot before going inactive
				log::system(dlog, ens, sys, T);
			}
			return ts.eject;
		}
	};

	/// CPU state and interface for stop_on_ejection
	gpu_t gpu_obj;

	stop_on_ejection(const config &cfg)
	{
		if(!cfg.count("rmax"))
		{
			gpu_obj.rmax = std::numeric_limits<float>::max();
		}
		else
		{
			gpu_obj.rmax = atof(cfg.at("rmax").c_str());
		}
	}

 	// currently empty for stop_on_ejection
	void initialize(ensemble &ens)
	{
		// Here you'd upload any temporary data you need to constant/texture/global memory
	}

 	// return gpu data for stop_on_ejection
	operator gpu_t()
	{
		return gpu_obj;
	}
};
#endif

/// factory to return a pointer to a gpu_generic_integrator using the Euler propagator and the stop_on_ejection stopper
extern "C" integrator *create_gpu_euler(const config &cfg)
{
	return new gpu_generic_integrator<stop_on_ejection, prop_euler>(cfg);
}

} // end namespace swarm
