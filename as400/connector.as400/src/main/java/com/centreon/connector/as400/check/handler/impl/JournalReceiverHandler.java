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
import java.util.HashMap;
import java.util.Properties;

import com.ibm.as400.access.AS400;
import com.ibm.as400.access.AS400JDBCDriver;
import com.centreon.connector.as400.check.handler.IJournalReceiverHandler;
import com.centreon.connector.as400.dispatcher.check.ResponseData;

/**
 * Attached journal receivers and their last sequence number (QSYS2.JOURNAL_RECEIVER_INFO).
 * Used to detect journals approaching the sequence number limit (CHGJRN ... SEQOPT(*RESET) needed).
 */
public class JournalReceiverHandler extends AbstractHandler implements IJournalReceiverHandler {

    public JournalReceiverHandler(final String host, final String login, final String password, final Integer ssl) {
        super(host, login, password, ssl);
    }

    @Override
    public ResponseData getJournalReceivers(final long minSequence, final boolean excludeMaxOpt3) throws Exception {
        String sql = "SELECT JOURNAL_LIBRARY, JOURNAL_NAME, JOURNAL_RECEIVER_LIBRARY, JOURNAL_RECEIVER_NAME,"
                + " LAST_SEQUENCE_NUMBER, CHAR(ATTACH_TIMESTAMP), RECEIVER_MAXIMUM_SIZE"
                + " FROM QSYS2.JOURNAL_RECEIVER_INFO WHERE STATUS = 'ATTACHED'"
                + " AND LAST_SEQUENCE_NUMBER > " + minSequence;
        if (excludeMaxOpt3) {
            sql += " AND RECEIVER_MAXIMUM_SIZE <> '*MAXOPT3'";
        }

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
                attrs.put("journalLibrary", trim(rs.getString(1)));
                attrs.put("journalName", trim(rs.getString(2)));
                attrs.put("receiverLibrary", trim(rs.getString(3)));
                attrs.put("receiverName", trim(rs.getString(4)));
                attrs.put("sequence", rs.getLong(5));
                attrs.put("attachTimestamp", trim(rs.getString(6)));
                attrs.put("maximumSize", trim(rs.getString(7)));
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

    private static String trim(final String s) {
        return s == null ? "" : s.trim();
    }
}
