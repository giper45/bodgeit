<%@ page import="java.sql.*" %>
<%@ page import="com.thebodgeitstore.util.Database" %>
<%@ page import="com.thebodgeitstore.util.DatabaseBootstrap" %>
<%!
	public void jspInit() {
		getServletContext().log("InitServlet init TheBodgeItStore :)");

		Connection c = null;
		try {
			Database.resetIfConfigured();
			c = Database.getConnection();
			DatabaseBootstrap.initialize(c);
		} catch (Exception e) {
			getServletContext().log("ERROR: failed to initialize the database: " + e);
		} finally {
			try {
				if (c != null) {
					c.close();
				}
			} catch (Exception e) {
			}
		}
	}

	public void jspDestroy() {
	}
%>
