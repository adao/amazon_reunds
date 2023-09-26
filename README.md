# AR

Finds discrepancies in Amazon billing for orders placed in Amazon marketplace.


## To run

You can clone the repository and run

```zsh
AR_USERNAME='email' AR_PASSWORD='password' mix run -e "AR.get_order_summary()"
```

which outputs the orders in which the aggregated totals of the two methods do not match up.

The first method uses the transaction history listed on Amazon.

The second method uses the 'Grand Total' and 'Refund' fields from the Order Details page. 
