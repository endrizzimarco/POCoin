<script setup>
import WalletSendForm from '@/components/WalletSendForm.vue'
import { QuestionCircleOutlined, ArrowLeftOutlined, ArrowRightOutlined } from '@ant-design/icons-vue'
import { useWalletStore } from '@/stores/wallets'
import { computed } from 'vue'

const props = defineProps({
  wallet: String
})

const store = useWalletStore()
const state = computed(() => store.wallet[props.wallet])

const addressesTableCols = [
  {
    title: 'Address',
    dataIndex: 'address',
    key: 'address'
  },
  {
    title: 'Balance',
    dataIndex: 'balance',
    key: 'balance',
    align: 'right'
  }
]
const transactionsTableCols = [
  {
    title: 'Block',
    dataIndex: 'block',
    key: 'block',
    width: 8,
    align: 'centre'
  },
  {
    title: 'Type',
    dataIndex: 'type',
    key: 'type',
    width: 10
  },
  {
    title: 'Transaction ID',
    dataIndex: 'txid',
    key: 'txid'
  },
  {
    title: 'Amount',
    dataIndex: 'amount',
    key: 'amount',
    width: 10,
    align: 'right'
  }
]

const getAddressPubPrivKeys = (addr, addresses) => {
  return addresses.find(x => Object.keys(x)[0] === addr)[addr]
}
</script>

<template lang="pug">
a-row.balance
  a-col(:span='12')
    a-statistic(:value='state.total_balance', :precision='2')
      template(#title)
        span Total Balance
        a-tooltip(placement='right')
          template(#title)
            span Available UTXOs + pending change
          question-circle-outlined.ml-1(style='font-size: 14px; bottom: 1px')
  a-col(:span='12')
    a-statistic(:value='state.available_balance', :precision='2')
      template(#title)
        span Available Balance
        a-tooltip(placement='right')
          template(#title)
            span Available UTXOs only
          question-circle-outlined.ml-1(style='font-size: 14px; bottom: 1px')

.utxos.mt-6
  p.pb-3.opacity-50(style='font-weight: 420') Available UTXOs
  a-table(
    :columns='addressesTableCols',
    :data-source='state.available_utxos',
    size='small',
    :pagination='{ hideOnSinglePage: true, pageSize: 3, size: "small" }'
  )
    template(#bodyCell='{ column, record }')
      template(v-if='column.key === "balance"')
        p {{ record['balance'].toFixed(2) }}
    template(#expandedRowRender='{ record }')
      p
        span.font-medium Public key:
        span &nbsp; {{ getAddressPubPrivKeys(record['address'], state.addresses)[0].substring(0, 35) }}
      p
        span.font-medium Private key:
        span &nbsp; {{ getAddressPubPrivKeys(record['address'], state.addresses)[1].substring(0, 35) }}
  a-alert.z-50.absolute.w-full.top-5(v-if='state.next_pending', type='info', closable)
    template(#description)
      a-spin.mr-4
      span.font-semibold Pending Transaction
      p.ml-12
        span.font-semibold To Address:
        span &nbsp; {{ state.next_pending[0] }}
      p.ml-12
        span.font-semibold Amount:
        span &nbsp; {{ state.next_pending[1] }}

.past-transactions.mt-5
  p.pb-3.opacity-50(style='font-weight: 420') Past Transactions
  a-table(
    :columns='transactionsTableCols',
    :data-source='state.history',
    size='small',
    :pagination='{ hideOnSinglePage: true, pageSize: 4, size: "small" }'
  )
    template(#bodyCell='{ column, record }')
      template(v-if='column.key === "amount"')
        p {{ record['amount'].toFixed(2) }}
      template(v-else-if='column.key === "type"')
        a-tag(v-if='record["type"] === "send"', color='volcano')
          arrow-right-outlined
          span SEND
        a-tag(v-else, color='success')
          arrow-left-outlined(style='bottom: 1px')
          span RECEIVE

.send-coins.mt-4
  p.opacity-50.mt-3(style='font-weight: 420') Send coins
  WalletSendForm.mt-2(:w='props.wallet')
</template>
