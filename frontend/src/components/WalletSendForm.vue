<script setup>
import { useWalletStore } from '@/stores/wallets'
import { ref, computed, watch } from 'vue'
import { message } from 'ant-design-vue'
import axios from 'axios'

const props = defineProps({
  w: String
})

const amount = ref()
const toAddress = ref()

const store = useWalletStore()
const available_balance = computed(() => store.wallet[props.w].available_balance)
const addresses = computed(() => store.wallet[props.w].available_balance)

const sendCoins = async (wallet, to_addr, amount) => {
  const r = await axios.get('http://localhost:3000/send_coins', {
    params: {
      wallet,
      to_addr,
      amount
    }
  })
  r.status === 200 ? message.success(r) : message.error(r)
}
</script>

<template lang="pug">
a-form(layout='inline')
  a-form-item
    a-input-number(v-model='amount', placeholder='Amount', :min='0', :max='available_balance', style='width: 100px')
  a-form-item
    a-select(v-model='to_addr', placeholder='Address', style='width: 320px')
      a-select-opt-group(v-for='wallet in ["alice", "bob", "charlie", "master"]')
        template(#label)
          span {{ wallet }}
        a-select-option(v-for='address in store.addresses[wallet]', :key='address', :value='address') {{ address }}
  a-form-item
    a-button(@click='sendCoins(props.w, toAddress, amount)') Send
</template>
