interface LEDBlink {
	command void report_problem();
	command void report_sent();
	command void report_received();
	command void report_dropped();
}