# Power BI build guide

Builds the 3-page dashboard from the CSVs in `powerbi/data/`.
Time: about 1-2 hours in Power BI Desktop (free, Windows).

Before you start: run `./run_pipeline.sh` (or use the CSVs already in
`powerbi/data/`) and have `measures.dax` open next to Power BI.

---

## Step 1 - Load the data (10 min)

1. **Home -> Get data -> Text/CSV**, pick `fct_orders.csv` -> **Transform Data**
   (not Load). Repeat for the other 4 CSVs; they all open in Power Query.
2. In Power Query, check the column types (icon left of each header):

   | Table | Column | Type |
   |---|---|---|
   | fct_orders | order_date, order_month | **Date** |
   | fct_orders | gmv, item_revenue, freight_revenue, delivery_days, promised_days | **Decimal number** |
   | fct_orders | is_delivered, is_late, review_score, days_late, item_count, max_installments | **Whole number** |
   | fct_order_items | price, freight_value, line_gmv | **Decimal number** |
   | dim_customer | monetary | **Decimal number** |
   | all ID columns | | **Text** |

   If Power BI guessed a type wrong, click the icon and change it.
3. **Close & Apply**.

## Step 2 - Date table (5 min)

1. **Modeling -> New table**, paste the `Date = ...` block from `measures.dax`.
2. Select the new `Date` table -> **Table tools -> Mark as date table** -> column `Date`.
3. Select column `Month` -> **Column tools -> Sort by column -> Month Start**.

## Step 3 - Relationships (10 min)

Open **Model view** (third icon on the left). Delete any relationships
Power BI auto-created, then drag to create these (all *many-to-one, single
direction*):

| From (many side) | To (one side) |
|---|---|
| fct_orders[order_date] | Date[Date] |
| fct_orders[customer_unique_id] | dim_customer[customer_unique_id] |
| fct_order_items[order_id] | fct_orders[order_id] |
| fct_order_items[product_id] | dim_product[product_id] |
| fct_order_items[seller_id] | dim_seller[seller_id] |

Result: a star schema. Date / customer filters flow to orders and on to
items, so category charts also react to date and state slicers.

## Step 4 - Measures (15 min)

Select table `fct_orders` -> **Home -> New measure**, paste one measure from
`measures.dax`, Enter. Repeat for every measure. Then format:

- Total GMV, GMV Prev Month, GMV 3M Avg, AOV, Item GMV: Currency, 0 decimals
- Late Rate, Negative Review Rate, GMV MoM %, Category Share %, Repeat Customer Rate,
  Segment GMV Share %: Percentage, 1 decimal
- Avg Review, Avg Delivery Days: 2 decimals

**Check your numbers** with a card for each (no filters applied):

| Measure | Expected |
|---|---|
| Total GMV | 15,683,707 |
| Orders | 97,905 |
| AOV | 160.19 |
| Customers | 94,703 |
| Avg Review | 4.12 |
| Late Rate | 6.8% |
| Negative Review Rate | 13.8% |
| Repeat Customer Rate | 3.0% |

If they match, the model is correct.

## Step 5 - Page 1: Executive Overview (20 min)

- **6 Card visuals** across the top: Total GMV, Orders, AOV, Customers, Avg Review, Late Rate.
- **Line and clustered column chart**: X = `Date[Month]`, column y = `Total GMV`,
  line y = `GMV 3M Avg`. Title: "Monthly GMV".
- **Clustered bar chart**: Y = `dim_product[category]`, X = `Item GMV`.
  Filters pane -> category -> Filter type **Top N**, Show items Top 10 by `Item GMV`.
- **Slicers**: `Date[Year]` (tile style), `dim_customer[customer_state]` (dropdown),
  `fct_orders[payment_type]` (dropdown).

## Step 6 - Page 2: Delivery & Satisfaction (20 min)

- **Clustered column chart**: X = `fct_orders[delay_bucket]`, Y = `Avg Review`.
  Add `Negative Review Rate` to tooltips. This is the headline insight.
- **Clustered bar chart**: Y = `dim_customer[customer_state]`, X = `Late Rate`,
  sorted descending. Conditional formatting -> Bars -> color red when >= 10%.
- **Scatter chart**: Values = `dim_customer[customer_state]`,
  X = `Avg Delivery Days`, Y = `Avg Review`, Size = `Orders`.
- **Cards**: Late Rate, Avg Delivery Days, Negative Review Rate.

## Step 7 - Page 3: Customers & Payments (20 min)

- **Clustered bar chart**: Y = `dim_customer[segment]`,
  X = `Customers` and `Segment GMV Share %` (or use a table with both).
- **Card**: Repeat Customer Rate (the "97% buy once" story).
- **Matrix**: Rows = `fct_orders[payment_type]`, Columns = `fct_orders[max_installments]`
  (or group into bins), Values = `Orders`, `AOV`.
- **Donut chart**: Legend = `fct_orders[payment_type]`, Values = `Orders`.

## Step 8 - Polish and export (10 min)

- **View -> Themes**: pick one theme and keep colors consistent
  (red = bad / late, blue = normal).
- Give each page a title text box and a one-line takeaway, e.g.
  *"Orders 4+ days late average 2.1 stars vs 4.3 on time."*
- **File -> Save as** `powerbi/olist_dashboard.pbix`.
- Take a screenshot of each page (Windows: `Win + Shift + S`), save as
  `reports/figures/dashboard_overview.png`, `dashboard_delivery.png`,
  `dashboard_customers.png`. They are referenced in the README.

Send the .pbix and screenshots back and they get committed to the repo.
