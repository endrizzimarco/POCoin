<script setup>
import axios from 'axios'
import { ref, onMounted, computed } from 'vue'

const blockchain = ref([])

const poll_blockchain = async () => {
  blockchain.value = await (await axios.get('http://localhost:3000/blockchain?node=n1')).data
}

onMounted(() => {
  poll_blockchain()
  setInterval(poll_blockchain, 1000)
})

// crimes against humanity
const toTreeData = json => {
  let treeData = []
  for (const key of Object.keys(json)) {
    let leaf = {
      key: key,
      title: json[key]
    }
    switch (key) {
      case 'height':
        continue
      case 'prev_hash':
      case 'txid':
        leaf.title = leaf?.title?.slice(0, 25)
        break
      case 'transaction':
        leaf.title = ''
        leaf.children = toTreeData(json[key])
        break
      case 'outputs':
      case 'inputs':
      case 'signatures':
        leaf.children = []
        leaf.title = ''
        for (const item of json[key]) {
          leaf.children.push({
            key: Math.random(),
            title: item?.slice(0, 25)
          })
        }
        break
    }
    if (key == 'txid') {
      treeData = [leaf, ...treeData]
    } else treeData.push(leaf)
  }
  return treeData
}
</script>

<template lang="pug">
.mx-2.overflow-y-scroll(style='height: 90vh')
  TransitionGroup(name='slide-fade')
    .px-3(v-for='(block, i) in blockchain', :key='block.height')
      .text-center(v-if='i != 0')
        a-divider.bg-slate-400.h-5(type='vertical', style='width: 2px')
      p.bg-white.pl-8.pt-2.text-lg.rounded-t-lg.font-semibold.underline.text-zinc-600 Block {{ i + 1 }}
      a-tree.shadow-md.rounded-b-lg.p-1.transition(:tree-data='toTreeData(block)')
        template(#title='{ title, key }')
          span.font-medium {{ typeof key != 'number' ? key + ': ' : '' }}
          span {{ title }}
</template>

<style>
.slide-fade-enter-active {
  transition: all 0.5s ease-out;
}

.slide-fade-enter-from,
.slide-fade-leave-to {
  transform: translateY(100px);
  opacity: 0.5;
}

::-webkit-scrollbar {
  -webkit-appearance: none;
  width: 7px;
}
::-webkit-scrollbar-thumb {
  border-radius: 4px;
  background-color: rgba(0, 0, 0, 0.2);
  -webkit-box-shadow: 0 0 1px rgba(255, 255, 255, 0.5);
}
</style>
