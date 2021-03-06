/*************************************************************************
 * Copyright (C) 2011 by Saleh Dindar and the Swarm-NG Development Team  *
 *                                                                       *
 * This program is free software; you can redistribute it and/or modify  *
 * it under the terms of the GNU General Public License as published by  *
 * the Free Software Foundation; either version 3 of the License.        *
 *                                                                       *
 * This program is distributed in the hope that it will be useful,       *
 * but WITHOUT ANY WARRANTY; without even the implied warranty of        *
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the         *
 * GNU General Public License for more details.                          *
 *                                                                       *
 * You should have received a copy of the GNU General Public License     *
 * along with this program; if not, write to the                         *
 * Free Software Foundation, Inc.,                                       *
 * 59 Temple Place - Suite 330, Boston, MA  02111-1307, USA.             *
 ************************************************************************/

/*! \file swarm.h
 *   \brief Public interface for swarmng library. 
 *
 *   User application intending to use swarm library should include this header file.
 *   This file has most of essential headers needed to use the swarmng library.
 *
*/
#pragma once

#include "common.hpp"
#include "types/ensemble.hpp"
#include "types/config.hpp"
#include "log/logmanager.hpp"
#include "integrator.hpp"
#include "plugin.hpp"
#include "utils.hpp"
#include "gpu/device_settings.hpp"

/// \defgroup integrators Integrators
/// \defgroup propagators Propagators
/// \defgroup monitors Monitors
/// \defgroup monitors_param Monitor Parameters

/*! Swarm-NG library
 *
 */
namespace swarm {

/*! Initialize the swarm library.
 *   This function is included for compatibility. 
 *  It is not mandatory to call this functions but it is
 *  encouraged for forward compatibility.
 */
inline void init(const config &cfg) { 
	// Select the proper device
	const char* devstr = getenv("CUDA_DEVICE");
	const int env_dev = (devstr != NULL) ? atoi(devstr) : 0;

	const int dev = cfg.optional("CUDA_DEVICE", env_dev);

	select_cuda_device(dev);

	if(cfg.optional("more_cache",0)!=0){
		set_more_cache();
	}

	print_device_information();


	swarm::log::manager::default_log()->init(cfg);
}


} 
