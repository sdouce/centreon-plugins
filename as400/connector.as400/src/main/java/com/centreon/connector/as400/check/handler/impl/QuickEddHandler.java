/*
 * Copyright 2026 Centreon (http://www.centreon.com/)
 *
 * Centreon is a full-fledged industry-strength solution that meets
 * the needs in IT infrastructure and application monitoring for
 * service performance.
 * 
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License. 
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software 
 * distributed under the License is distributed on an "AS IS" BASIS, 
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. 
 * See the License for the specific language governing permissions and 
 * limitations under the License.
 */

package com.centreon.connector.as400.check.handler.impl;

import java.sql.Connection;
import java.sql.ResultSet;
import java.sql.Statement;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Properties;
import java.util.Set;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

import com.ibm.as400.access.AS400;
import com.ibm.as400.access.AS400JDBCDriver;
import com.ibm.as400.access.AS400Message;
import com.ibm.as400.access.AS400Text;
import com.ibm.as400.access.CommandCall;
import com.ibm.as400.access.ProgramParameter;
import com.ibm.as400.access.ServiceProgramCall;
import com.centreon.connector.as400.ConnectorLogger;
import com.centreon.connector.as400.check.handler.IQuickEddHandler;
import com.centreon.connector.as400.dispatcher.check.ResponseData;

/**
 * QuickEDD (HA replication) checks.
 *
 * Environment checks call the QuickEDD service program &lt;libProg&gt;/PZHAWRKM with the same
 * procedures and parameter layout as the historical edh_status.jar probe:
 * init_wrkm2, EnvIsActive, EnvError, getEnvWait, EnvDelayJrn, getEnvList.
 * The licence check reads &lt;libLicense&gt;.EDHCHKLIC through the jt400 JDBC driver.
 */
public class QuickEddHandler extends AbstractHandler implements IQuickEddHandler {

    private static final String SRVPGM = "PZHAWRKM";
    private static final Pattern NAME = Pattern.compile("^[A-Z0-9#@$_]{1,6}$");

    public QuickEddHandler(final String host, final String login, final String password, final Integer ssl) {
        super(host, login, password, ssl);
    }

    /* ------------------------------------------------------------------ */
    /* service program helpers                                             */
    /* ------------------------------------------------------------------ */

    private static void checkLibrary(final String lib, final String option) throws Exception {
        if (lib != null && !lib.matches("^[A-Za-z0-9#@$_]{1,10}$")) {
            throw new Exception("invalid library name for " + option + ": " + lib);
        }
    }

    private static void addLible(final AS400 system, final String lib) throws Exception {
        if (lib == null || lib.isEmpty()) {
            return;
        }
        final CommandCall cmd = new CommandCall(system);
        if (!cmd.run("ADDLIBLE LIB(" + lib + ")")) {
            for (final AS400Message m : cmd.getMessageList()) {
                // CPF2103: library already in the library list -> not an error
                if (!"CPF2103".equals(m.getID())) {
                    ConnectorLogger.getInstance().debug("ADDLIBLE " + lib + ": " + m.getID() + " " + m.getText());
                }
            }
        }
    }

    private static void call(final ServiceProgramCall spgm, final String procedure, final ProgramParameter[] params,
            final boolean intReturn) throws Exception {
        spgm.setReturnValueFormat(intReturn ? ServiceProgramCall.RETURN_INTEGER : ServiceProgramCall.NO_RETURN_VALUE);
        spgm.setParameterList(params);
        spgm.setProcedureName(procedure);
        if (!spgm.run()) {
            final StringBuilder sb = new StringBuilder("call " + procedure + " failed");
            for (final AS400Message m : spgm.getMessageList()) {
                sb.append(" - ").append(m.getID()).append(' ').append(m.getText());
            }
            throw new Exception(sb.toString());
        }
    }

    /** Library list + ServiceProgramCall + init_wrkm2() (same sequence as edh_status.jar). */
    private static ServiceProgramCall init(final AS400 system, final String libQedd, final String libProg)
            throws Exception {
        addLible(system, libQedd);
        addLible(system, libProg);
        final ServiceProgramCall spgm = new ServiceProgramCall(system);
        spgm.setProgram("/QSYS.LIB/" + libProg + ".LIB/" + SRVPGM + ".SRVPGM");

        final ProgramParameter[] p = new ProgramParameter[4];
        p[0] = new ProgramParameter(new AS400Text(2, system).toBytes("**"));
        p[1] = new ProgramParameter(new byte[] { 0, 33 }, 2);
        p[2] = new ProgramParameter(3);
        p[3] = new ProgramParameter(new byte[64000], 64000);
        call(spgm, "init_wrkm2__FPcsT1", p, false);
        return spgm;
    }

    /** procedure(char *out, char *env): returns the text written in the output buffer. */
    private static String envProc(final AS400 system, final ServiceProgramCall spgm, final String procedure,
            final String env, final int outLength) throws Exception {
        final AS400Text tEnv = new AS400Text(6, system);
        final AS400Text tOut = new AS400Text(outLength, system);
        final ProgramParameter[] p = new ProgramParameter[2];
        p[0] = new ProgramParameter(ProgramParameter.PASS_BY_REFERENCE, outLength);
        p[1] = new ProgramParameter(ProgramParameter.PASS_BY_REFERENCE, tEnv.toBytes(env), 6);
        call(spgm, procedure, p, true);
        final String value = ((String) tOut.toObject(p[0].getOutputData())).trim();
        ConnectorLogger.getInstance().debug("QuickEDD " + procedure + "(" + env + ") = [" + value + "]");
        return value;
    }

    private static long toLong(final String value, final String what, final String env) throws Exception {
        try {
            return Long.parseLong(value.trim());
        } catch (final NumberFormatException e) {
            throw new Exception("non numeric " + what + " value for environment " + env + ": [" + value + "]");
        }
    }

    private static String rawEnvList(final AS400 system, final ServiceProgramCall spgm) throws Exception {
        final ProgramParameter[] p = new ProgramParameter[1];
        p[0] = new ProgramParameter(ProgramParameter.PASS_BY_REFERENCE, 32000);
        call(spgm, "getEnvList__FPc", p, true);
        return ((String) new AS400Text(32000, system).toObject(p[0].getOutputData())).trim();
    }

    /** Best effort split of getEnvList output into environment names (to be validated on real systems). */
    static List<String> splitEnvList(final String raw) {
        final Set<String> names = new LinkedHashSet<String>();
        for (final String token : raw.toUpperCase().split("[\\s,;|]+")) {
            final Matcher m = NAME.matcher(token);
            if (m.matches()) {
                names.add(token);
            }
        }
        return new ArrayList<String>(names);
    }

    /* ------------------------------------------------------------------ */
    /* checks                                                              */
    /* ------------------------------------------------------------------ */

    @Override
    public ResponseData getEnvironments(final String libQeddArg, final String libProgArg, final List<String> environments)
            throws Exception {
        final String libQedd = libQeddArg == null ? null : libQeddArg.toUpperCase();
        final String libProg = libProgArg == null ? null : libProgArg.toUpperCase();
        if (libProg == null || libProg.isEmpty()) {
            return new ResponseData(ResponseData.statusError, "Invalid arguments. please set libProg");
        }
        checkLibrary(libQedd, "libQedd");
        checkLibrary(libProg, "libProg");

        final ResponseData data = new ResponseData();
        final AS400 system = this.getNewAs400();
        try {
            final ServiceProgramCall spgm = init(system, libQedd, libProg);

            List<String> envs = environments;
            if (envs == null || envs.isEmpty()) {
                envs = splitEnvList(rawEnvList(system, spgm));
            }

            for (final String envName : envs) {
                final String env = envName.trim().toUpperCase();
                final HashMap<String, Object> attrs = new HashMap<String, Object>();
                attrs.put("name", env);
                try {
                    if (!NAME.matcher(env).matches()) {
                        throw new Exception("invalid environment name (6 characters max)");
                    }
                    final long active = toLong(envProc(system, spgm, "EnvIsActive__FPcT1", env, 2), "active", env);
                    attrs.put("active", active == 0 ? "inactive" : (active == -1 ? "unknown" : "active"));
                    attrs.put("errors", toLong(envProc(system, spgm, "EnvError__FPcT1", env, 2), "errors", env));
                    attrs.put("waiting", toLong(envProc(system, spgm, "getEnvWait__FPcT1", env, 64), "wait", env));
                    attrs.put("delay", toLong(envProc(system, spgm, "EnvDelayJrn__FPcT1", env, 64), "delay", env));
                    attrs.put("status", "success");
                } catch (final Exception e) {
                    attrs.put("status", "failed");
                    attrs.put("message", e.getMessage());
                    ConnectorLogger.getInstance().debug("QuickEDD environment " + env, e);
                }
                data.getResult().add(attrs);
            }
        } finally {
            system.disconnectAllServices();
        }
        return data;
    }

    @Override
    public ResponseData listEnvironments(final String libQeddArg, final String libProgArg) throws Exception {
        final String libQedd = libQeddArg == null ? null : libQeddArg.toUpperCase();
        final String libProg = libProgArg == null ? null : libProgArg.toUpperCase();
        if (libProg == null || libProg.isEmpty()) {
            return new ResponseData(ResponseData.statusError, "Invalid arguments. please set libProg");
        }
        checkLibrary(libQedd, "libQedd");
        checkLibrary(libProg, "libProg");

        final ResponseData data = new ResponseData();
        final AS400 system = this.getNewAs400();
        try {
            final ServiceProgramCall spgm = init(system, libQedd, libProg);
            final String raw = rawEnvList(system, spgm);
            for (final String name : splitEnvList(raw)) {
                final HashMap<String, Object> attrs = new HashMap<String, Object>();
                attrs.put("name", name);
                data.getResult().add(attrs);
            }
            data.setMessage(raw);
        } finally {
            system.disconnectAllServices();
        }
        return data;
    }

    @Override
    public ResponseData getLicense(final String libLicense) throws Exception {
        final String lib = (libLicense == null || libLicense.isEmpty()) ? "PMEDHUSR" : libLicense.toUpperCase();
        checkLibrary(lib, "libLicense");

        final String sql = "SELECT CHAR(ADTEADD), ZZCHK,"
                + " CASE WHEN CURRENT TIMESTAMP > ADTEADD - ZZCHK DAYS THEN 1 ELSE 0 END,"
                + " TIMESTAMPDIFF(16, CAST(ADTEADD - CURRENT TIMESTAMP AS CHAR(22)))"
                + " FROM " + lib + ".EDHCHKLIC";

        final ResponseData data = new ResponseData();
        final AS400 system = this.getNewAs400();
        Connection cx = null;
        try {
            final Properties props = new Properties();
            props.put("naming", "sql");
            props.put("errors", "full");
            props.put("prompt", "false");
            cx = new AS400JDBCDriver().connect(system, props, null);
            final Statement st = cx.createStatement();
            final ResultSet rs = st.executeQuery(sql);
            while (rs.next()) {
                final HashMap<String, Object> attrs = new HashMap<String, Object>();
                attrs.put("expiration", rs.getString(1) == null ? "" : rs.getString(1).trim());
                attrs.put("checkDays", rs.getLong(2));
                attrs.put("inCheckPeriod", rs.getInt(3));
                attrs.put("daysLeft", rs.getLong(4));
                data.getResult().add(attrs);
            }
            rs.close();
            st.close();
        } finally {
            if (cx != null) {
                cx.close();
            }
            system.disconnectAllServices();
        }
        return data;
    }
}
