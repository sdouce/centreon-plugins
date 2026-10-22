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
import java.sql.ResultSetMetaData;
import java.sql.Statement;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Locale;
import java.util.Properties;

import com.ibm.as400.access.AS400;
import com.ibm.as400.access.AS400JDBCDriver;
import com.centreon.connector.as400.check.handler.ISqlHandler;
import com.centreon.connector.as400.dispatcher.check.ResponseData;

/**
 * Read-only SQL query (SELECT / WITH / VALUES) through the jt400 JDBC driver.
 * The connection is opened with access=read only, so the driver itself refuses any update.
 * Result: one entry { columns: [...], rows: [[...], ...], truncated: 0|1 }.
 */
public class SqlHandler extends AbstractHandler implements ISqlHandler {

    public SqlHandler(final String host, final String login, final String password, final Integer ssl) {
        super(host, login, password, ssl);
    }

    @Override
    public ResponseData executeQuery(final String request, final int maxRows) throws Exception {
        if (request == null || request.trim().isEmpty()) {
            return new ResponseData(ResponseData.statusError, "Invalid arguments. please set request");
        }
        String sql = request.trim();
        while (sql.endsWith(";")) {
            sql = sql.substring(0, sql.length() - 1).trim();
        }
        final String first = sql.split("[\\s(]+", 2)[0].toUpperCase(Locale.ROOT);
        if (!(first.equals("SELECT") || first.equals("WITH") || first.equals("VALUES"))) {
            return new ResponseData(ResponseData.statusError, "Only read-only queries are allowed (SELECT, WITH, VALUES)");
        }
        if (sql.indexOf(';') >= 0) {
            return new ResponseData(ResponseData.statusError, "Only one query is allowed");
        }
        final int limit = maxRows <= 0 ? 100 : maxRows;

        final ResponseData data = new ResponseData();
        final AS400 system = this.getNewAs400();
        Connection cx = null;
        try {
            final Properties props = new Properties();
            props.put("naming", "sql");
            props.put("errors", "full");
            props.put("prompt", "false");
            props.put("access", "read only");
            props.put("translate binary", "true");
            cx = new AS400JDBCDriver().connect(system, props, null);
            cx.setReadOnly(true);
            final Statement st = cx.createStatement();
            st.setMaxRows(limit + 1);
            final ResultSet rs = st.executeQuery(sql);
            final ResultSetMetaData md = rs.getMetaData();
            final int n = md.getColumnCount();

            final List<String> columns = new ArrayList<String>();
            for (int c = 1; c <= n; c++) {
                columns.add(md.getColumnLabel(c));
            }
            final List<List<String>> rows = new ArrayList<List<String>>();
            int truncated = 0;
            while (rs.next()) {
                if (rows.size() >= limit) {
                    truncated = 1;
                    break;
                }
                final List<String> row = new ArrayList<String>();
                for (int c = 1; c <= n; c++) {
                    final String v = rs.getString(c);
                    row.add(v == null ? null : v.trim());
                }
                rows.add(row);
            }
            rs.close();
            st.close();

            final HashMap<String, Object> attrs = new HashMap<String, Object>();
            attrs.put("columns", columns);
            attrs.put("rows", rows);
            attrs.put("truncated", truncated);
            data.getResult().add(attrs);
        } finally {
            if (cx != null) {
                cx.close();
            }
            system.disconnectAllServices();
        }
        return data;
    }
}
