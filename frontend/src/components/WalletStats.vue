<script setup>
import WalletSendForm from '@/components/WalletSendForm.vue'
import { defineProps, computed } from 'vue'
import { useWalletStore } from '@/stores/wallets'
import { message } from 'ant-design-vue'
import axios from 'axios'

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
    width: 10,
    align: 'right'
  }
]
const transactionsTableCols = [
  {
    title: 'Block',
    dataIndex: 'block',
    key: 'block',
    width: 8
  },
  {
    title: 'Type',
    dataIndex: 'type',
    key: 'type'
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

const generateAddress = async () => {
  const response = await axios.get('http://localhost:3000/generate_address', {
    params: {
      wallet: props.wallet
    }
  })
  response.status === 200
    ? message.success('Successfully generated address')
    : message.error('Failed to generate address')

  //console.log('wallet', props.wallet)
}
</script>

<template lang="pug">
a-row
  a-col(:span='12')
    a-statistic(title='Total Balance', :precision=2, :value='state.total_balance')
  a-col(:span='12')
    a-statistic(title='Available Balance', :precision=2, :value='state.available_balance')
.mt-5
  p.pb-3.opacity-50(style='font-weight: 420') Available UTXOs
  a-table(:columns='addressesTableCols', :data-source='state.available_utxos', size='small', :pagination='false')
    template(#bodycell='{ column, text }')
      template(v-if='column.dataIndex === "name"')
        a {{ text }}
    template(#expandedRowRender='{ record }')
      p
        span.font-medium Public key:
        span &nbsp; {{ getAddressPubPrivKeys(record['address'], state.addresses)[0].substring(0, 25) }}
      p
        span.font-medium Private key:
        span &nbsp; {{ getAddressPubPrivKeys(record['address'], state.addresses)[1].substring(0, 25) }}
  br
  p.pb-3.opacity-50(style='font-weight: 420') Past Transactions
  p {{ store.history }}
  a-table(
    :columns='transactionsTableCols',
    :data-source='state.history',
    size='small',
    :pagination='{ hideOnSinglePage: true, pageSize: 5 }'
  )
    template(#bodycell='{ column, text }')
      template(v-if='column.dataIndex === "name"')
        a {{ text }}
p.pt-6.opacity-50(style='font-weight: 420') Generate Address
a-button.mt-2(@click='generateAddress') Generate Address
p.pt-6.opacity-50(style='font-weight: 420') Send coins
WalletSendForm.mt-2(:w='props.wallet')
</template>
