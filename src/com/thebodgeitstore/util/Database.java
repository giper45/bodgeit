package com.thebodgeitstore.util;

import java.io.File;
import java.sql.Connection;
import java.sql.DriverManager;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.sql.SQLException;

public final class Database {

    private static final String DRIVER_CLASS = "org.sqlite.JDBC";
    private static final String DATABASE_PATH_PROPERTY = "bodgeit.db.path";
    private static final String DATABASE_RESET_PROPERTY = "bodgeit.db.reset";

    private Database() {
    }

    public static Connection getConnection() throws ClassNotFoundException, SQLException {
        Class.forName(DRIVER_CLASS);
        ensureParentDirectoryExists();
        return DriverManager.getConnection(getJdbcUrl());
    }

    public static void resetIfConfigured() throws SQLException {
        String reset = System.getProperty(DATABASE_RESET_PROPERTY);
        if ("false".equalsIgnoreCase(reset)) {
            return;
        }

        File databaseFile = getDatabaseFile();
        if (databaseFile.exists() && !databaseFile.delete()) {
            throw new SQLException("Failed to delete database file " + databaseFile.getAbsolutePath());
        }
    }

    public static boolean tableExists(Connection connection, String tableName) throws SQLException {
        PreparedStatement stmt = null;
        ResultSet rs = null;
        try {
            stmt = connection.prepareStatement(
                "SELECT name FROM sqlite_master WHERE type = 'table' AND name = ?");
            stmt.setString(1, tableName);
            rs = stmt.executeQuery();
            return rs.next();
        } finally {
            closeQuietly(rs);
            closeQuietly(stmt);
        }
    }

    private static String getJdbcUrl() {
        return "jdbc:sqlite:" + getDatabaseFile().getAbsolutePath();
    }

    private static File getDatabaseFile() {
        String databasePath = System.getProperty(DATABASE_PATH_PROPERTY);
        if (databasePath == null || databasePath.trim().length() == 0) {
            databasePath = System.getProperty("java.io.tmpdir") + File.separator + "bodgeit.sqlite";
        }
        return new File(databasePath);
    }

    private static void ensureParentDirectoryExists() throws SQLException {
        File parent = getDatabaseFile().getAbsoluteFile().getParentFile();
        if (parent != null && !parent.exists() && !parent.mkdirs()) {
            throw new SQLException("Failed to create database directory " + parent.getAbsolutePath());
        }
    }

    private static void closeQuietly(ResultSet rs) {
        if (rs != null) {
            try {
                rs.close();
            } catch (Exception e) {
            }
        }
    }

    private static void closeQuietly(PreparedStatement stmt) {
        if (stmt != null) {
            try {
                stmt.close();
            } catch (Exception e) {
            }
        }
    }
}
