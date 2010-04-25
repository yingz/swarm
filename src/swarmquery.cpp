//
// C++ Implementation: swarmquery
//
// Description: 
//
//
// Author: Mario Juric <mjuric@cfa.harvard.edu>, (C) 2010
//
// Copyright: See COPYING file that comes with this distribution
//
//

//
// Examples:
//	swarmquery -T 10-20 -sys 5-END
//
//	
//

#include <iostream>
#include <string>
#include <sstream>
#include <boost/program_options.hpp>
#include <boost/regex.hpp>
#include <dlfcn.h>

#include "swarmio.h"

// using namespace boost;
// using namespace boost::program_options;

namespace swarm
{
	template<typename T>
	T arg_parse(const std::string &s)
	{
		if(s == "MIN") { return MIN; }
		if(s == "MAX") { return MAX; }
		return boost::lexical_cast<T>(s);
	}

	//
	// Parse ranges of the form:
	//	<r1>..<r2>
	//	MIN..<r2>
	//	<r1>..MAX
	//	ALL
	//
	template<typename T>
	void validate(boost::any& v,
		const std::vector<std::string>& values,
		range<T>* target_type, int)
	{
		using namespace boost::program_options;
		typedef range<T> rangeT;

		// Make sure no previous assignment to 'a' was made.
		validators::check_first_occurrence(v);

		// Extract the first string from 'values'. If there is more than
		// one string, it's an error, and exception will be thrown.
		const std::string& s = validators::get_single_string(values);

		if(s == "ALL")
		{
			v = boost::any(rangeT(ALL));
			return;
		}

		static boost::regex r("(.+?)(?:\\.\\.(.+))?");
		boost::smatch match;
		if (boost::regex_match(s, match, r)) {
			//for(int i=0; i != match.size(); i++) { std::cerr << match[i] << "\n"; }
			if(match[2] == "")
			{
				v = boost::any(rangeT(arg_parse<T>(match[1])));
			}
			else
			{
				v = boost::any(rangeT(arg_parse<T>(match[1]), arg_parse<T>(match[2])));
			}
		} else {
#if BOOST_VERSION  < 104200
			throw validation_error("invalid value");
#else
			throw validation_error(validation_error::invalid_option_value);
#endif
		}
	}

	template<typename T>
	std::ostream &operator<<(std::ostream &out, const swarm::range<T> &r)
	{
		if(r.first == T(MIN) && r.last == T(MAX)) { return out << "ALL"; }
		if(r.first == r.last) { return out << r.first; }

		if(r.first == T(MIN)) { out << "MIN"; } else { out << r.first; }
		out << "..";
		if(r.last == T(MAX)) { out << "MAX"; } else { out << r.last; }

		return out;
	}
}

void get_Tsys(gpulog::logrecord &lr, double &T, int &sys)
{
	//std::cerr << "msgid=" << lr.msgid() << "\n";
	if(lr.msgid() < 0)
	{
		// system-defined events that have no (T,sys) heading
		T = -1; sys = -1;
	}
	else
	{
		lr >> T >> sys;
	}
}

// Default output, if no handler is registered
std::ostream& record_output_default(std::ostream &out, gpulog::logrecord &lr)
{
	double T; int sys;
	get_Tsys(lr, T, sys);
	out << lr.msgid() << "\t" << T << "\t" << sys;
	return out;
}

// EVT_SNAPSHOT
extern "C" std::ostream& record_output_1(std::ostream &out, gpulog::logrecord &lr)
{
	double T;
	int nbod, sys, flags;
	const swarm::body *bodies;
	lr >> T >> sys >> flags >> nbod >> bodies;

	char buf[1000];
	for(int bod = 0; bod != nbod; bod++)
	{
		const swarm::body &b = bodies[bod];

		if(bod != 0) { out << "\n"; }
		sprintf(buf, "%10d %f  %5d %5d  %f  % 9.5f % 9.5f % 9.5f  % 9.5f % 9.5f % 9.5f  %d", lr.msgid(), T, sys, bod, b.m, b.x, b.y, b.z, b.vx, b.vy, b.vz, flags);
		out << buf;
	}
	return out;
}

// EVT_EJECTION
extern "C" std::ostream& record_output_2(std::ostream &out, gpulog::logrecord &lr)
{
	double T;
	int sys;
	swarm::body b;
	lr >> T >> sys >> b;

	char buf[1000];
	sprintf(buf, "%10d %f  %5d %5d  %f  % 9.5f % 9.5f % 9.5f  % 9.5f % 9.5f % 9.5f", lr.msgid(), T, sys, b.bod, b.m, b.x, b.y, b.z, b.vx, b.vy, b.vz);
	out << buf;

	return out;
}

typedef std::ostream& (*record_output_function_t)(std::ostream &out, gpulog::logrecord &lr);
std::ostream &output_record(std::ostream &out, gpulog::logrecord &lr)
{
	int evtid = lr.msgid();

	static std::map<int, record_output_function_t> cache;
	if(!cache.count(evtid))
	{
		void *me = dlopen(NULL, RTLD_LAZY);
		if(me == NULL) { ERROR(dlerror()); }

		std::ostringstream ss;
		ss << "record_output_" << evtid;
		std::string fnname = ss.str();

		record_output_function_t fun = (record_output_function_t)dlsym(me, fnname.c_str());
		cache[evtid] = fun ? fun : record_output_default;
	}

	record_output_function_t fun = cache.at(evtid);
	return fun(out, lr);
}

void execute_query(const std::string &datafile, swarm::time_range_t T, swarm::sys_range_t sys)
{
	using namespace swarm;

	swarmdb db(datafile);
	swarmdb::result r = db.query(sys, T);
	gpulog::logrecord lr;
	while(lr = r.next())
	{
		output_record(std::cout, lr);
		std::cout << "\n";
	}
}

int main(int argc, char **argv)
{
	namespace po = boost::program_options;
	using namespace swarm;

	po::options_description desc(std::string("Usage: ") + argv[0] + " <datafile>\n\nOptions");
	desc.add_options()
		("help", "produce help message")
		("time,t", po::value<time_range_t>(), "range of times to query")
		("system,s", po::value<sys_range_t>(), "range of systems to query")
		("datafile", po::value<std::string>(), "the datafile to query")
	;
	po::positional_options_description pd;
	pd.add("datafile", 1);

	po::variables_map vm;
	po::store(po::command_line_parser(argc, argv).options(desc).allow_unregistered().positional(pd).run(), vm);
	po::notify(vm);

	if (vm.count("help") || !vm.count("datafile")) { std::cout << desc << "\n"; return 1; }

	time_range_t T;
	sys_range_t sys;
	if (vm.count("time")) { T = vm["time"].as<time_range_t>(); }
	if (vm.count("system")) { sys = vm["system"].as<sys_range_t>(); }

        std::cout.flush(); 
	std::cerr << "Printing outputs satisfying T=" << T << " sys=" << sys << "\n";

	std::string datafile(vm["datafile"].as<std::string>());

	execute_query(datafile, T, sys);
}
