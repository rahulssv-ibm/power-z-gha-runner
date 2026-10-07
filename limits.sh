#!/bin/bash

echo "==========================="
echo "System Limits Information"
echo "==========================="

echo ""
echo "1. Current User Limits (ulimit)"
echo "-------------------------------"
ulimit -a

echo ""
echo "2. System-Wide Open File Descriptor Limits"
echo "------------------------------------------"
echo "Maximum number of open file descriptors:"
cat /proc/sys/fs/file-max

echo ""
echo "3. System-Wide Process Limits"
echo "-----------------------------"
echo "Maximum number of processes:"
cat /proc/sys/kernel/pid_max
echo "Maximum number of threads per process:"
cat /proc/sys/kernel/threads-max

echo ""
echo "4. Pipe Buffer Size"
echo "-------------------"
cat /proc/sys/fs/pipe-max-size

echo ""
echo "5. Per-User Limits (from limits.conf and limits.d)"
echo "-------------------------------------------------"
echo "Contents of /etc/security/limits.conf:"
cat /etc/security/limits.conf 2>/dev/null || echo "File not found."
echo ""
echo "Contents of /etc/security/limits.d/:"
ls /etc/security/limits.d/ 2>/dev/null || echo "Directory not found."

echo ""
echo "6. Default Shell and Login Limits"
echo "---------------------------------"
echo "Contents of /etc/profile:"
cat /etc/profile 2>/dev/null || echo "File not found."
echo ""
echo "Contents of /etc/bashrc:"
cat /etc/bashrc 2>/dev/null || echo "File not found."
echo ""
echo "Contents of PAM configuration files:"
echo "common-session:"
cat /etc/pam.d/common-session 2>/dev/null || echo "File not found."
echo "common-session-noninteractive:"
cat /etc/pam.d/common-session-noninteractive 2>/dev/null || echo "File not found."

echo ""
echo "7. Process-Specific Limits"
echo "--------------------------"
echo "For the current shell (PID $$):"
cat /proc/$$/limits

echo ""
echo "8. Open File Descriptors for Current Shell"
echo "------------------------------------------"
echo "Number of open file descriptors:"
ls -l /proc/$$/fd | wc -l

echo ""
echo "9. System-Wide File Descriptor Usage"
echo "------------------------------------"
echo "Allocated, Free, and System-Wide Limit:"
cat /proc/sys/fs/file-nr

echo ""
echo "10. Real-Time Open File Descriptor Monitoring"
echo "---------------------------------------------"
echo "Total number of open file descriptors (using lsof):"
lsof | wc -l

echo ""
echo "10. Get PAGESIZE"
echo "------------------------------------"
echo "Page Size:"
getconf PAGESIZE
echo ""
echo "==========================="
echo "End of System Limits Report"
echo "==========================="
