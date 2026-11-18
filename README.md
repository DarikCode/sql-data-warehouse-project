# Sales Data Analytics with SQL

[![Built with Data With Baraa](https://img.shields.io/badge/Built_with-Data_With_Baraa-F5B301?style=for-the-badge)](https://github.com/DataWithBaraa/sql-data-analytics-project)
![SQL Server](https://img.shields.io/badge/SQL_Server-CC2927?style=for-the-badge&logo=microsoftsqlserver&logoColor=white)

An end-to-end SQL analysis of a retail sales data warehouse, from initial data exploration to customer and product reports that support business decisions.

---

## 📘 Overview

The project analyzes sales, customer and product data stored in SQL Server. It is divided into two stages: **exploratory data analysis**, which builds an understanding of the data, and **advanced analytics**, which answers business questions and delivers reporting views ready for BI tools.

## 🔍 Business Questions

- How have sales developed over time, and do they show seasonality?
- Which products and categories generate the most revenue, and which underperform?
- How are customers segmented, and what is the value of each segment?
- How does each product perform against its own average and the previous year?

## 🔧 Tools and Skills

| Area | Details |
|---|---|
| **Database** | SQL Server, SSMS |
| **SQL** | Joins, aggregations, CTEs, window functions (`SUM() OVER`, `LAG`, `AVG() OVER`), `CASE` logic, views |
| **Analytics** | EDA, trend analysis, running totals, performance analysis, part-to-whole, segmentation, reporting |

## 🔬 Analysis

### Exploratory Data Analysis
Database structure, dimensions, date ranges, key business measures (total sales, orders, customers), magnitude analysis by country and category, and ranking of top and bottom performers.

### Advanced Analytics
Change-over-time trends, cumulative totals and moving averages, year-over-year product performance, category contribution to total sales, and customer and product segmentation.

### Reports
Two SQL views consolidate the key metrics into a single source for dashboards:
- **Customer report:** segments, age groups, recency, order count, average order value and monthly spend.
- **Product report:** performance tiers, revenue, recency, average selling price and monthly revenue.

## 💎 Key Findings

- Total sales of **€X** across **X** orders and **X** customers (20XX–20XX).
- **[Category]** accounts for **X%** of total revenue, indicating a high dependency on a single category.
- **X%** of customers are classified as VIP and generate **X%** of revenue.
- Sales peak consistently in **[month]**.
- **[Product]** has performed below its average for **X** consecutive years and is a candidate for review.

## ▶️ How to Run

1. Install SQL Server (Express or Developer edition) and SSMS.
2. Restore the database from the `.bak` file, or run `00_init_database.sql` after updating the CSV file path.
3. Execute the scripts in numerical order.

## 💙 Credits

Dataset and project structure by **Baraa Khatib Salkini** ([Data With Baraa](https://github.com/DataWithBaraa/sql-data-analytics-project)), used under the MIT License.

## 👤 About Me

**Ildar Mamin** is an M.Sc. (Tech) student in Industrial Engineering and Management at LUT University, Finland, specializing in data analytics for decision-making.

[LinkedIn](https://www.linkedin.com/in/your-profile) · [Email](mailto:your.email@example.com)
